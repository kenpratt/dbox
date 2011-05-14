require File.expand_path(File.dirname(__FILE__) + "/spec_helper")

include FileUtils

describe Dbox do
  before(:each) do
    cd LOCAL_TEST_PATH
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
      rm_rf @local
      expect { Dbox.create(@remote) }.to raise_error("Remote path already exists")
      File.exists?(@local).should be_false
    end
  end

  describe "#clone" do
    it "creates the local directory" do
      Dbox.create(@remote)
      rm_rf @local
      File.exists?(@local).should be_false
      Dbox.clone(@remote)
      File.exists?(@local).should be_true
    end

    it "should fail if the remote does not exist" do
      expect { Dbox.clone(@remote) }.to raise_error(Dbox::RemoteMissing)
      File.exists?(@local).should be_false
    end
  end

  describe "#pull" do
    it "should fail if the local dir is missing" do
      expect { Dbox.pull(@local) }.to raise_error(Dbox::MissingDatabase)
    end

    it "should fail if the remote dir is missing" do
      Dbox.create(@remote)
      modify_dbfile {|s| s.sub(/^remote_path: \/.*$/, "remote_path: /#{randname()}") }
      expect { Dbox.pull(@local) }.to raise_error(Dbox::RemoteMissing)
    end

    it "should be able to pull" do
      Dbox.create(@remote)
      expect { Dbox.pull(@local) }.to_not raise_error
    end

    it "should be able to pull from inside the dir" do
      Dbox.create(@remote)
      cd @local
      expect { Dbox.pull }.to_not raise_error
    end

    it "should be able to pull changes" do
      Dbox.create(@remote)
      File.exists?("#{@local}/hello.txt").should be_false

      cd ALTERNATE_LOCAL_TEST_PATH
      Dbox.clone(@remote)
      cd @name
      touch "hello.txt"
      Dbox.push

      expect { Dbox.pull(@local) }.to_not raise_error
      File.exists?("#{@local}/hello.txt").should be_true
    end

    it "should be able to pull after deleting a file and not have the file re-created" do
      Dbox.create(@remote)
      cd @name
      touch "hello.txt"
      Dbox.push
      Dbox.pull
      rm "hello.txt"
      Dbox.pull
      File.exists?("#{@local}/hello.txt").should be_false
    end
  end

  describe "#push" do
    it "should fail if the local dir is missing" do
      expect { Dbox.push(@local) }.to raise_error(Dbox::MissingDatabase)
    end

    it "should be able to push" do
      Dbox.create(@remote)
      expect { Dbox.push(@local) }.to_not raise_error
    end

    it "should be able to push from inside the dir" do
      Dbox.create(@remote)
      cd @local
      expect { Dbox.push }.to_not raise_error
    end

    it "should be able to push new file" do
      Dbox.create(@remote)
      touch File.join(@local, "foo.txt")
      expect { Dbox.push(@local) }.to_not raise_error
    end

    it "should create the remote dir if it is missing" do
      Dbox.create(@remote)
      touch File.join(@local, "foo.txt")
      @new_name = randname()
      @new_remote = File.join(REMOTE_TEST_PATH, @new_name)
      modify_dbfile {|s| s.sub(/^remote_path: \/.*$/, "remote_path: #{@new_remote}") }
      expect { Dbox.push(@local) }.to_not raise_error
    end
  end
end
