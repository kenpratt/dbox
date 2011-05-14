require File.expand_path(File.dirname(__FILE__) + "/spec_helper")

describe Dbox do
  before(:each) do
    Dir.chdir(LOCAL_TEST_PATH)
  end

  describe "#create" do
    before(:each) do
      @dir = randname()
      @path = File.join(LOCAL_TEST_PATH, @dir)
    end

    it "creates the local directory" do
      Dbox.create(@dir)
      File.exists?(@path).should be_true
    end
  end

  describe "#clone" do
    before(:each) do
      @dir = randname()
      @path = File.join(LOCAL_TEST_PATH, @dir)
    end

    it "creates the local directory" do
      Dbox.create(@dir)
      FileUtils.rm_rf(@path)
      File.exists?(@path).should be_false
      Dbox.clone(@dir)
      File.exists?(@path).should be_true
    end

    it "should fail if the remote does not exist" do
      expect { Dbox.clone(@dir) }.to raise_error("Remote path does not exist")
      File.exists?(@path).should be_false
    end
  end
end
