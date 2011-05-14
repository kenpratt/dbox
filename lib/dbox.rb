ROOT_PATH = File.expand_path(File.join(File.dirname(__FILE__), ".."))
$:.unshift File.join(ROOT_PATH, "lib")
$:.unshift File.join(ROOT_PATH, "vendor", "dropbox-client-ruby", "lib")

require "dbox/client_api"
require "dbox/db"
require "fileutils"

# load config
CONFIG_FILE = File.join(ROOT_PATH, "config", "dropbox.json")
CONF = Authenticator.load_config(CONFIG_FILE)

# usage line
def usage
  "Usage:
  dbox authorize
  export DROPBOX_AUTH_KEY=abcdef012345678
  export DROPBOX_AUTH_SECRET=876543210fedcba
  dbox create <remote_path> [<local_path>]
  dbox clone <remote_path> [<local_path>]
  dbox pull
  dbox push"
end
def print_usage_and_quit; puts usage; exit 1; end

# ensure that push/pull arg was given
print_usage_and_quit unless ARGV.size > 0

# execute the command
case command = ARGV[0]

when "authorize"
  # get access tokens
  Dbox::API.authorize

when "create", "clone"
  # grab remote path
  remote_path = ARGV[1] ? ARGV[1].sub(/\/$/,'') : nil
  unless remote_path && remote_path.any?
    puts "Error: Please provide a remote path to clone"
    print_usage_and_quit
  end
  remote_path = "/#{remote_path}" unless remote_path[0] == "/"

  # grab or infer local path
  local_path = ARGV[2] || remote_path.split("/").last

  # execute create/clone
  Dbox::Db.send(command, remote_path, local_path)

when "pull", "push"
  # grab local path or use current directory
  # TODO search upward for .dropbox.db file like git does?
  local_path = ARGV[1] || "."

  # load the db into memory
  db = Dbox::Db.load(local_path)

  # execute the push/pull
  db.send(command)

else
  print_usage_and_quit

end
