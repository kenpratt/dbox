require File.expand_path(File.dirname(__FILE__) + "/spec_helper")

describe Dbox do
  before(:each) do
    Dir.chdir(TEST_REPO_DIR)
  end

  describe "#create" do
    before(:each) do
      @dir = randname()
      @path = File.join(TEST_REPO_DIR, @dir)
    end

    it "creates the local directory" do
      Dbox.create(@dir)
      File.exists?(@path).should be_true
    end
  end
end
