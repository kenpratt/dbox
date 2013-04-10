module Dbox
  NUM_TRIES = 3
  TIME_BETWEEN_TRIES = 3 # in seconds

  class ConfigurationError < RuntimeError; end
  class ServerError < RuntimeError; end
  class RemoteMissing < RuntimeError; end
  class RemoteAlreadyExists < RuntimeError; end
  class RequestDenied < RuntimeError; end

  class API
    include Loggable

    def self.authorize
      app_key = ENV["DROPBOX_APP_KEY"]
      app_secret = ENV["DROPBOX_APP_SECRET"]

      raise(ConfigurationError, "Please set the DROPBOX_APP_KEY environment variable to a Dropbox application key") unless app_key
      raise(ConfigurationError, "Please set the DROPBOX_APP_SECRET environment variable to a Dropbox application secret") unless app_secret

      auth = DropboxSession.new(app_key, app_secret)
      puts "Please visit the following URL in your browser, log into Dropbox, and authorize the app you created.\n\n#{auth.get_authorize_url}\n\nWhen you have done so, press [ENTER] to continue."
      STDIN.readline
      res = auth.get_access_token
      puts "export DROPBOX_AUTH_KEY=#{res.key}"
      puts "export DROPBOX_AUTH_SECRET=#{res.secret}"
      puts
      puts "This auth token will last for 10 years, or when you choose to invalidate it, whichever comes first."
      puts
      puts "Now either include these constants in yours calls to dbox, or set them as environment variables."
      puts "In bash, including them in calls looks like:"
      puts "$ DROPBOX_AUTH_KEY=#{res.key} DROPBOX_AUTH_SECRET=#{res.secret} dbox ..."
    end

    def self.connect
      api = new()
      api.connect
      api
    end

    attr_reader :client

    # IMPORTANT: API.new is private. Please use API.authorize or API.connect as the entry point.
    private_class_method :new
    def initialize
    end

    def initialize_copy(other)
      @client = other.client.clone()
    end

    def connect
      app_key = ENV["DROPBOX_APP_KEY"]
      app_secret = ENV["DROPBOX_APP_SECRET"]
      auth_key = ENV["DROPBOX_AUTH_KEY"]
      auth_secret = ENV["DROPBOX_AUTH_SECRET"]
      access_type = ENV["DROPBOX_ACCESS_TYPE"] || "dropbox" # "app_folder"

      raise(ConfigurationError, "Please set the DROPBOX_APP_KEY environment variable to a Dropbox application key") unless app_key
      raise(ConfigurationError, "Please set the DROPBOX_APP_SECRET environment variable to a Dropbox application secret") unless app_secret
      raise(ConfigurationError, "Please set the DROPBOX_AUTH_KEY environment variable to an authenticated Dropbox session key") unless auth_key
      raise(ConfigurationError, "Please set the DROPBOX_AUTH_SECRET environment variable to an authenticated Dropbox session secret") unless auth_secret
      raise(ConfigurationError, "Please set the DROPBOX_ACCESS_TYPE environment variable either dropbox (full access) or sandbox (App access)") unless access_type == "dropbox" || access_type == "app_folder"

      @session = DropboxSession.new(app_key, app_secret)
      @session.set_access_token(auth_key, auth_secret)
      @client = DropboxClient.new(@session, access_type)
    end

    def run(path, tries = NUM_TRIES, &proc)
      begin
        res = proc.call
        handle_response(path, res) { raise RuntimeError, "Unexpected result: #{res.inspect}" }
      rescue DropboxNotModified => e
        :not_modified
      rescue DropboxAuthError => e
        raise e
      rescue DropboxError => e
        if tries > 0
          if e.http_response.kind_of?(Net::HTTPServiceUnavailable)
            log.info "Encountered 503 on #{path} (likely rate limiting). Sleeping #{TIME_BETWEEN_TRIES}s and trying again."
            # TODO check for "Retry-After" header and use that for sleep instead of TIME_BETWEEN_TRIES
            log.info "Headers: #{e.http_response.to_hash.inspect}"
          else
            log.info "Encountered a dropbox error. Sleeping #{TIME_BETWEEN_TRIES}s and trying again. Error: #{e.inspect}"
            log.info "Headers: #{e.http_response.to_hash.inspect}"
          end
          sleep TIME_BETWEEN_TRIES
          run(path, tries - 1, &proc)
        else
          handle_response(path, e.http_response) { raise ServerError, "Server error -- might be a hiccup, please try your request again (#{e.message})" }
        end
      rescue Exception => e
        if tries > 0
          log.info "Encounted an unknown error. Sleeping #{TIME_BETWEEN_TRIES}s and trying again. Error: #{e.inspect}"
          sleep TIME_BETWEEN_TRIES
          run(path, tries - 1, &proc)
        else
          raise e
        end
      end
    end

    def handle_response(path, res, &else_proc)
      case res
      when Hash
        InsensitiveHash[res]
      when String
        res
      when Net::HTTPNotFound
        raise RemoteMissing, "#{path} does not exist on Dropbox"
      when Net::HTTPForbidden
        raise RequestDenied, "Operation on #{path} denied"
      when Net::HTTPNotModified
        :not_modified
      when true
        true
      else
        else_proc.call()
      end
    end

    def metadata(path = "/", hash = nil, list=true)
      run(path) do
        log.debug "Fetching metadata for #{path}"
        res = @client.metadata(path, 10000, list, hash)
        log.debug res.inspect
        raise Dbox::RemoteMissing, "#{path} has been deleted on Dropbox" if res["is_deleted"]
        res
      end
    end

    def create_dir(path)
      run(path) do
        log.info "Creating #{path}"
        begin
          @client.file_create_folder(path)
        rescue DropboxError => e
          if e.http_response.kind_of?(Net::HTTPForbidden)
            raise RemoteAlreadyExists, "Either the directory at #{path} already exists, or it has invalid characters in the name"
          else
            raise e
          end
        end
      end
    end

    def delete_dir(path)
      run(path) do
        log.info "Deleting #{path}"
        @client.file_delete(path)
      end
    end

    def get_file(path, file_obj, stream=false)
      unless stream
        # just download directly using the get_file API
        res = run(path) do
          log.info "Downloading #{path}"
          @client.get_file(path)
        end
        if res.kind_of?(String)
          file_obj << res
          true
        else
          raise DropboxError.new("Invalid response #{res.inspect}")
        end
      else
        # use the media API to get a URL that we can stream from, and
        # then stream the file to disk
        res = run(path) { @client.media(path) }
        url = res[:url] if res && res.kind_of?(Hash)
        if url
          log.info "Downloading #{path}"
          streaming_download(url, file_obj)
        else
          get_file(path, file_obj, false)
        end
      end
    end

    def put_file(path, local_path, previous_revision=nil)
      run(path) do
        log.info "Uploading #{path}"
        File.open(local_path, "r") {|f| @client.put_file(path, f, false, previous_revision) }
      end
    end

    def delete_file(path)
      run(path) do
        log.info "Deleting #{path}"
        @client.file_delete(path)
      end
    end

    def move(old_path, new_path)
      run(old_path) do
        log.info "Moving #{old_path} to #{new_path}"
        begin
          @client.file_move(old_path, new_path)
        rescue DropboxError => e
          if e.http_response.kind_of?(Net::HTTPForbidden)
            raise RemoteAlreadyExists, "Error during move -- there may already be a Dropbox folder at #{new_path}"
          else
            raise e
          end
        end
      end
    end

    def streaming_download(url, io, num_redirects = 0)
      url = URI.parse(url)
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.ca_file = Dropbox::TRUSTED_CERT_FILE

      req = Net::HTTP::Get.new(url.request_uri)
      req["User-Agent"] = "OfficialDropboxRubySDK/#{Dropbox::SDK_VERSION}"

      http.request(req) do |res|
        if res.kind_of?(Net::HTTPSuccess)
          # stream into given io
          res.read_body {|chunk| io.write(chunk) }
          true
        else
          if res.kind_of?(Net::HTTPRedirection) && res.header['location'] && num_redirects < 10
            log.info("following redirect, num_redirects = #{num_redirects}")
            log.info("redirect url: #{res.header['location']}")
            streaming_download(res.header['location'], io, num_redirects + 1)
          else
            raise DropboxError.new("Invalid response #{res.inspect}")
          end
        end
      end
    end
  end
end
