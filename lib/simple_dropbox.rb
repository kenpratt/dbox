ROOT_PATH = File.expand_path(File.join(File.dirname(__FILE__), ".."))
$:.unshift File.join(ROOT_PATH, "lib")
$:.unshift File.join(ROOT_PATH, "vendor", "dropbox-client-ruby", "lib")

require "simple_dropbox/client_api"
require "simple_dropbox/db"
require "optparse"
require "fileutils"

# load config
CONFIG_FILE = File.join(ROOT_PATH, "config", "dropbox.json")
CONF = Authenticator.load_config(CONFIG_FILE)

# usage line
def usage
  "Usage:
  simple-dropbox authorize
  DROPBOX_AUTH_KEY=\"...\" DROPBOX_AUTH_SECRET=\"...\" simple-dropbox pull [-r remote/path] [-l local/path]
  DROPBOX_AUTH_KEY=\"...\" DROPBOX_AUTH_SECRET=\"...\" simple-dropbox push [-r remote/path] [-l local/path]"
end
def print_usage_and_quit; puts usage; exit 1; end

# parse command-line options, overriding local_path and remote_path in config file if necessary
options = {}
OptionParser.new do |opts|
  opts.banner = usage

  opts.on("-r", "--remote-path PATH", "Specify remote path to sync") do |path|
    CONF["remote_path"] = path
  end

  opts.on("-l", "--local-path PATH", "Specify local path to save files in (either absolute or relative to project root)") do |path|
    CONF["local_path"] = path
  end
end.parse!

# resolve paths
raise "Please pass in --remote-path command-line option or remote_path in the config file." unless CONF["remote_path"]
REMOTE_PATH = CONF["remote_path"]

raise "Please pass in --local-path command-line option or local_path in the config file." unless CONF["local_path"]
LOCAL_PATH = case local = CONF["local_path"]
             when /^\//
               local # absolute path
             else
               File.expand_path(File.join(ROOT_PATH, local)) # relative to project root
             end
# ensure that push/pull arg was given
print_usage_and_quit unless ARGV.size == 1

# initialize dropbox client & db
FileUtils.mkdir_p(LOCAL_PATH)

# execute the push or pull
case command = ARGV[0]
when "authorize"
  # get access tokens
  DropboxSync::ClientAPI.authorize
when "pull", "push"
  # actually push or pull

  # ensure that Dropbox auth key & secret are provided
  AUTH_KEY = ENV["DROPBOX_AUTH_KEY"] || raise("Must set DROPBOX_AUTH_KEY environment variable to an authenticated Dropbox session key")
  AUTH_SECRET = ENV["DROPBOX_AUTH_SECRET"] || raise("Must set DROPBOX_AUTH_SECRET environment variable to an authenticated Dropbox session secret")

  API = DropboxSync::ClientAPI.connect(AUTH_KEY, AUTH_SECRET)
  DB_FILE = File.expand_path(File.join(LOCAL_PATH, CONF["db_file"]))
  DB = DropboxSync::Db.load

  # execute the push/pull
  DB.send(command)

  # save the DB to disk
  DB.save
else
  print_usage_and_quit
end
