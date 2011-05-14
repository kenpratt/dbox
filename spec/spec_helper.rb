$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "..", "lib"))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require "rspec"
require "dbox"
require "fileutils"

TEST_REPO_DIR = File.expand_path(File.join(File.dirname(__FILE__), "..", "tmp", "test_repos"))
FileUtils.mkdir_p(TEST_REPO_DIR)

def randname
  u = `uuidgen`.chomp
  "test-#{u}"
end
