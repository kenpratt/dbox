module Dbox
  class API
    def self.connect(auth_key, auth_secret)
      api = new()
      api.connect(auth_key, auth_secret)
      api
    end

    # IMPORTANT: API.new is private. Please use API.connect as the entry point.
    private_class_method :new
    def initialize
    end

    def self.authorize
      auth = Authenticator.new(CONF)
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

    def connect(auth_key, auth_secret)
      @auth = Authenticator.new(CONF, auth_key, auth_secret)
      @client = DropboxClient.new(CONF["server"], CONF["content_server"] ,CONF["port"], @auth)
    end

    def metadata(path = "/")
      path = escape_path(path)
      puts "[api] fetching metadata for #{path}"
      @client.metadata(CONF["root"], path)
    end

    def create_dir(path)
      path = escape_path(path)
      puts "[api] creating #{path}"
      @client.file_create_folder(CONF["root"], path)
    end

    def delete_dir(path)
      path = escape_path(path)
      puts "[api] deleting #{path}"
      @client.file_delete(CONF["root"], path)
    end

    def get_file(path)
      path = escape_path(path)
      puts "[api] downloading #{path}"
      @client.get_file(CONF["root"], path)
    end

    def put_file(path, file_obj)
      path = escape_path(path)
      puts "[api] uploading #{path}"
      dir = File.dirname(path)
      name = File.basename(path)
      @client.put_file(CONF["root"], dir, name, file_obj)
    end

    def delete_file(path)
      path = escape_path(path)
      puts "[api] deleting #{path}"
      @client.file_delete(CONF["root"], path)
    end

    def escape_path(path)
      URI.escape(path)
    end
  end
end
