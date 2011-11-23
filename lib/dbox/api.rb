module Dbox
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

      raise(ConfigurationError, "Please set the DROPBOX_APP_KEY environment variable to a Dropbox application key") unless app_key
      raise(ConfigurationError, "Please set the DROPBOX_APP_SECRET environment variable to a Dropbox application secret") unless app_secret
      raise(ConfigurationError, "Please set the DROPBOX_AUTH_KEY environment variable to an authenticated Dropbox session key") unless auth_key
      raise(ConfigurationError, "Please set the DROPBOX_AUTH_SECRET environment variable to an authenticated Dropbox session secret") unless auth_secret

      @session = DropboxSession.new(app_key, app_secret)
      @session.set_access_token(auth_key, auth_secret)
      @client = DropboxClient.new(@session, 'dropbox')
    end

    def run(path)
      begin
        res = yield
        handle_response(path, res) { raise RuntimeError, "Unexpected result: #{res.inspect}" }
      rescue DropboxNotModified => e
        :not_modified
      rescue DropboxAuthError => e
        raise e
      rescue DropboxError => e
        handle_response(path, e.http_response) { raise ServerError, "Server error -- might be a hiccup, please try your request again (#{e.message})" }
      end
    end

    def handle_response(path, res, &else_proc)
      case res
      when Hash
        HashWithIndifferentAccess.new(res)
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
      log.debug "Fetching metadata for #{path}"
      run(path) do
        res = @client.metadata(path, 10000, list, hash)
        log.debug res.inspect
        res
      end
    end

    def create_dir(path)
      log.info "Creating #{path}"
      run(path) do
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
      log.info "Deleting #{path}"
      run(path) do
        @client.file_delete(path)
      end
    end

    def get_file(path, file_obj, stream=false)
      log.info "Downloading #{path}"
      unless stream
        # just download directly using the get_file API
        res = run(path) { @client.get_file(path) }
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
          streaming_download(url, file_obj)
        else
          get_file(path, file_obj, false)
        end
      end
    end

    def put_file(path, file_obj, previous_revision=nil)
      log.info "Uploading #{path}"
      run(path) do
        @client.put_file(path, file_obj, false, previous_revision)
      end
    end

    def delete_file(path)
      log.info "Deleting #{path}"
      run(path) do
        @client.file_delete(path)
      end
    end

    def move(old_path, new_path)
      log.info "Moving #{old_path} to #{new_path}"
      run(old_path) do
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

    def streaming_download(url, io)
      url = URI.parse(url)
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true

      req = Net::HTTP::Get.new(url.request_uri)
      req["User-Agent"] = "OfficialDropboxRubySDK/#{Dropbox::SDK_VERSION}"

      http.request(req) do |res|
        if res.kind_of?(Net::HTTPSuccess)
          # stream into given io
          res.read_body {|chunk| io.write(chunk) }
          true
        else
          raise DropboxError.new("Invalid response #{res}\n#{res.body}")
        end
      end
    end
  end
end

# monkey-patch DropboxSession to add SSL certificate checking, since the
# Dropbox Ruby SDK doesn't do it and doesn't have a place to hook into.
class DropboxSession
  private
  def do_http(uri, auth_token, request) # :nodoc:
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    # IMPORTANT: other than these two extra lines, this should be
    # identical to the definition in dropbox_sdk.rb
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.ca_file = File.join(File.dirname(__FILE__), "cacert.pem")

    request.add_field('Authorization', build_auth_header(auth_token))

    #We use this to better understand how developers are using our SDKs.
    request['User-Agent'] =  "OfficialDropboxRubySDK/#{Dropbox::SDK_VERSION}"

    http.request(request)
  end
end
