module Dbox
  class API
    def self.authorize
      puts conf.inspect
      auth = Authenticator.new(conf)
      puts auth.inspect
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

    # IMPORTANT: API.new is private. Please use API.authorize or API.connect as the entry point.
    private_class_method :new
    def initialize
      @conf = self.class.conf
    end

    def connect
      auth_key = ENV["DROPBOX_AUTH_KEY"]
      auth_secret = ENV["DROPBOX_AUTH_SECRET"]

      raise("Please set the DROPBOX_AUTH_KEY environment variable to an authenticated Dropbox session key") unless auth_key
      raise("Please set the DROPBOX_AUTH_SECRET environment variable to an authenticated Dropbox session secret") unless auth_secret

      @auth = Authenticator.new(@conf, auth_key, auth_secret)
      @client = DropboxClient.new(@conf["server"], @conf["content_server"], @conf["port"], @auth)
    end

    def metadata(path = "/")
      path = escape_path(path)
      puts "[api] fetching metadata for #{path}"
      case res = @client.metadata(@conf["root"], path)
      when Hash
        res
      when Net::HTTPNotFound
        raise "Remote path does not exist"
      when Net::HTTPInternalServerError
        puts res.inspect
        raise "Server error -- might be a hiccup, please try your request again"
      else
        raise "Unexpected result from GET /metadata: #{res.inspect}"
      end
    end

    def create_dir(path)
      path = escape_path(path)
      puts "[api] creating #{path}"
      @client.file_create_folder(@conf["root"], path)
    end

    def delete_dir(path)
      path = escape_path(path)
      puts "[api] deleting #{path}"
      @client.file_delete(@conf["root"], path)
    end

    def get_file(path)
      path = escape_path(path)
      puts "[api] downloading #{path}"
      @client.get_file(@conf["root"], path)
    end

    def put_file(path, file_obj)
      path = escape_path(path)
      puts "[api] uploading #{path}"
      dir = File.dirname(path)
      name = File.basename(path)
      @client.put_file(@conf["root"], dir, name, file_obj)
    end

    def delete_file(path)
      path = escape_path(path)
      puts "[api] deleting #{path}"
      @client.file_delete(@conf["root"], path)
    end

    def escape_path(path)
      URI.escape(path)
    end

    def self.conf
      app_key = ENV["DROPBOX_APP_KEY"]
      app_secret = ENV["DROPBOX_APP_SECRET"]

      raise("Please set the DROPBOX_APP_KEY environment variable to a Dropbox application key") unless app_key
      raise("Please set the DROPBOX_APP_SECRET environment variable to a Dropbox application secret") unless app_secret

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
