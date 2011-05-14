require File.expand_path(File.dirname(__FILE__) + "/spec_helper")

describe Dbox do
  before(:each) do
    Dir.chdir(LOCAL_TEST_PATH)
    @name = randname()
    @local = File.join(LOCAL_TEST_PATH, @name)
    @remote = File.join(REMOTE_TEST_PATH, @name)
  end

  describe "#create" do
    it "creates the local directory" do
      Dbox.create(@remote)
      File.exists?(@local).should be_true
    end

    xit "should fail if the remote already exists" do
      Dbox.create(@remote)
      FileUtils.rm_rf(@local)
      expect { Dbox.create(@remote) }.to raise_error("Remote path already exists")
      File.exists?(@local).should be_false
    end
  end

  describe "#clone" do
    it "creates the local directory" do
      Dbox.create(@remote)
      FileUtils.rm_rf(@local)
      File.exists?(@local).should be_false
      Dbox.clone(@remote)
      File.exists?(@local).should be_true
    end

    it "should fail if the remote does not exist" do
      expect { Dbox.clone(@remote) }.to raise_error("Remote path does not exist")
      File.exists?(@local).should be_false
    end
  end

  describe "#pull" do
    it "should fail if the local dir is missing" do
      expect { Dbox.pull }.to raise_error(/No DB file found/)
      expect { Dbox.pull(@local) }.to raise_error(/No DB file found/)
    end

    it "should fail if the remote repo is missing" do
      Dbox.create(@remote)
      modify_dbfile {|s| s.sub(/^remote_path: \/.*$/, "remote_path: /missing") }
      expect { Dbox.pull(@local) }.to raise_error("Remote path does not exist")
    end

    it "should fail if the remote does not exist" do
      expect { Dbox.clone(@remote) }.to raise_error("Remote path does not exist")
      File.exists?(@local).should be_false
    end
  end
end
