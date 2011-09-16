module Dbox
  class ConfigurationError < RuntimeError; end
  class ServerError < RuntimeError; end
  class RemoteMissing < RuntimeError; end
  class RemoteAlreadyExists < RuntimeError; end
  class RequestDenied < RuntimeError; end

  class API
    include Loggable

    def self.authorize
      auth = Authenticator.new(conf)
      authorize_url = auth.get_request_token
      puts "Please visit the following URL in your browser, log into Dropbox, and authorize the app you created.\n\n#{authorize_url}\n\nWhen you have done so, press [ENTER] to continue."
      STDIN.readline
      res = auth.get_access_token
      puts "export DROPBOX_AUTH_KEY=#{res.token}"
      puts "export DROPBOX_AUTH_SECRET=#{res.secret}"
      puts
      puts "This auth token will last for 10 years, or when you choose to invalidate it, whichever comes first."
      puts
      puts "Now either include these constants in yours calls to dbox, or set them as environment variables."
      puts "In bash, including them in calls looks like:"
      puts "$ DROPBOX_AUTH_KEY=#{res.token} DROPBOX_AUTH_SECRET=#{res.secret} dbox ..."
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
      @conf = self.class.conf
    end

    def initialize_copy(other)
      @client = other.client.clone()
    end

    def connect
      auth_key = ENV["DROPBOX_AUTH_KEY"]
      auth_secret = ENV["DROPBOX_AUTH_SECRET"]

      raise(ConfigurationError, "Please set the DROPBOX_AUTH_KEY environment variable to an authenticated Dropbox session key") unless auth_key
      raise(ConfigurationError, "Please set the DROPBOX_AUTH_SECRET environment variable to an authenticated Dropbox session secret") unless auth_secret

      @auth = Authenticator.new(@conf, auth_key, auth_secret)
      @client = DropboxClient.new(@conf["server"], @conf["content_server"], @conf["port"], @auth)
    end

    def run(path)
      begin
        res = yield
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
        else
          raise RuntimeError, "Unexpected result: #{res.inspect}"
        end
      rescue DropboxError => e
        log.debug e.inspect
        raise ServerError, "Server error -- might be a hiccup, please try your request again (#{e.message})"
      end
    end

    def metadata(path = "/", hash = nil)
      log.debug "Fetching metadata for #{path}"
      run(path) do
        res = @client.metadata(@conf["root"], escape_path(path), 10000, hash)
        log.debug res.inspect
        res
      end
    end

    def create_dir(path)
      log.info "Creating #{path}"
      run(path) do
        case res = @client.file_create_folder(@conf["root"], path)
        when Net::HTTPForbidden
          raise RemoteAlreadyExists, "Either the directory at #{path} already exists, or it has invalid characters in the name"
        else
          res
        end
      end
    end

    def delete_dir(path)
      log.info "Deleting #{path}"
      run(path) do
        @client.file_delete(@conf["root"], path)
      end
    end

    def get_file(path)
      log.info "Downloading #{path}"
      run(path) do
        @client.get_file(@conf["root"], escape_path(path))
      end
    end

    def put_file(path, file_obj)
      log.info "Uploading #{path}"
      run(path) do
        dir = File.dirname(path)
        name = File.basename(path)
        @client.put_file(@conf["root"], escape_path(dir), name, file_obj)
      end
    end

    def delete_file(path)
      log.info "Deleting #{path}"
      run(path) do
        @client.file_delete(@conf["root"], path)
      end
    end

    def move(old_path, new_path)
      log.info "Moving #{old_path} to #{new_path}"
      run(old_path) do
        case res = @client.file_move(@conf["root"], old_path, new_path)
        when Net::HTTPBadRequest
          raise RemoteAlreadyExists, "Error during move -- there may already be a Dropbox folder at #{new_path}"
        else
          res
        end
      end
    end

    def escape_path(path)
      path.split("/").map {|s| CGI.escape(s).gsub("+", "%20") }.join("/")
    end

    def self.conf
      app_key = ENV["DROPBOX_APP_KEY"]
      app_secret = ENV["DROPBOX_APP_SECRET"]

      raise(ConfigurationError, "Please set the DROPBOX_APP_KEY environment variable to a Dropbox application key") unless app_key
      raise(ConfigurationError, "Please set the DROPBOX_APP_SECRET environment variable to a Dropbox application secret") unless app_secret

      {
        "server"            => "api.dropbox.com",
        "content_server"    => "api-content.dropbox.com",
        "port"              => 80,
        "request_token_url" => "http://api.dropbox.com/0/oauth/request_token",
        "access_token_url"  => "http://api.dropbox.com/0/oauth/access_token",
        "authorization_url" => "http://www.dropbox.com/0/oauth/authorize",
        "root"              => "dropbox",
        "consumer_key"      => app_key,
        "consumer_secret"   => app_secret
      }
    end
  end
end
