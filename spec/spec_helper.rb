$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "..", "lib"))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require "rspec"
require "dbox"
require "fileutils"

LOCAL_TEST_PATH = File.expand_path(File.join(File.dirname(__FILE__), "..", "tmp", "test_dirs"))
ALTERNATE_LOCAL_TEST_PATH = File.join(LOCAL_TEST_PATH, "alternate")
FileUtils.mkdir_p(LOCAL_TEST_PATH)
FileUtils.mkdir_p(ALTERNATE_LOCAL_TEST_PATH)

REMOTE_TEST_PATH = "/dbox_test_dirs"

$started_at ||= Time.now

LOGFILE = File.expand_path(File.join(File.dirname(__FILE__), "..", "tmp", "test.log"))
LOGGER = Logger.new(LOGFILE)
LOGGER.formatter = proc do |severity, datetime, progname, msg|
  format "[%4.1fs] [%s] %s\n", (Time.now - $started_at), severity, msg
end

def randname
  u = `uuidgen`.chomp
  "test-#{u}"
end

def modify_dbfile
  dbfile = File.join(@local, Dbox::DB::DB_FILE)
  s = File.open(dbfile, "r").read
  s = yield s
  File.open(dbfile, "w") {|f| f << s }
end

def clear_test_log
  File.open(LOGFILE, "w") {|f| f << "" }
end

def log
  LOGGER
end
