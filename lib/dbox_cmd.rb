$:.unshift File.dirname(__FILE__)
require "dbox"

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
print_usage_and_quit unless ARGV.size >= 1

command = ARGV[0]
rest = ARGV[1..-1]

# execute the command
case command
when "authorize"
  Dbox.authorize
when "create", "clone"
  unless rest.size >= 1
    puts "Error: Please provide a remote path to clone"
    print_usage_and_quit
  end
  Dbox.send(command, *rest)
when "pull", "push"
  Dbox.send(command, *rest)
else
  print_usage_and_quit
end
