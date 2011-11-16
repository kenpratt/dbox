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
          raise RuntimeError, "Unexpected result: #{res.inspect}"
        end
      rescue DropboxNotModified => e
        :not_modified
      rescue DropboxError => e
        log.debug e.inspect
        raise ServerError, "Server error -- might be a hiccup, please try your request again (#{e.message})"
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
        case res = @client.file_create_folder(path)
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
        @client.file_delete(path)
      end
    end

    def get_file(path)
      log.info "Downloading #{path}"
      run(path) do
        @client.get_file(path)
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
        case res = @client.file_move(old_path, new_path)
        when Net::HTTPBadRequest
          raise RemoteAlreadyExists, "Error during move -- there may already be a Dropbox folder at #{new_path}"
        else
          res
        end
      end
    end
  end
end
