require File.expand_path(File.dirname(__FILE__) + "/spec_helper")

include FileUtils

describe Dbox do
  before(:all) do
    clear_test_log
  end

  before(:each) do
    log.info example.full_description
    @name = randname()
    @local = File.join(LOCAL_TEST_PATH, @name)
    @remote = File.join(REMOTE_TEST_PATH, @name)
  end

  after(:each) do
    log.info ""
  end

  describe "#create" do
    it "creates the local directory" do
      Dbox.create(@remote, @local)
      File.exists?(@local).should be_true
    end

    it "should fail if the remote already exists" do
      Dbox.create(@remote, @local)
      rm_rf @local
      expect { Dbox.create(@remote, @local) }.to raise_error(Dbox::RemoteAlreadyExists)
      File.exists?(@local).should be_false
    end
  end

  describe "#clone" do
    it "creates the local directory" do
      Dbox.create(@remote, @local)
      rm_rf @local
      File.exists?(@local).should be_false
      Dbox.clone(@remote, @local)
      File.exists?(@local).should be_true
    end

    it "should fail if the remote does not exist" do
      expect { Dbox.clone(@remote, @local) }.to raise_error(Dbox::RemoteMissing)
      File.exists?(@local).should be_false
    end
  end

  describe "#pull" do
    it "should fail if the local dir is missing" do
      expect { Dbox.pull(@local) }.to raise_error(Dbox::MissingDatabase)
    end

    it "should fail if the remote dir is missing" do
      Dbox.create(@remote, @local)
      modify_dbfile {|s| s.sub(/^remote_path: \/.*$/, "remote_path: /#{randname()}") }
      expect { Dbox.pull(@local) }.to raise_error(Dbox::RemoteMissing)
    end

    it "should be able to pull" do
      Dbox.create(@remote, @local)
      expect { Dbox.pull(@local) }.to_not raise_error
    end

    it "should be able to pull from inside the dir" do
      Dbox.create(@remote, @local)
      expect { Dbox.pull(@local) }.to_not raise_error
    end

    it "should be able to pull changes" do
      Dbox.create(@remote, @local)
      File.exists?("#{@local}/hello.txt").should be_false

      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)
      touch "#{@alternate}/hello.txt"
      Dbox.push(@alternate)

      expect { Dbox.pull(@local) }.to_not raise_error
      File.exists?("#{@local}/hello.txt").should be_true
    end

    it "should be able to pull after deleting a file and not have the file re-created" do
      Dbox.create(@remote, @local)
      touch "#{@local}/hello.txt"
      Dbox.push(@local)
      Dbox.pull(@local)
      rm "#{@local}/hello.txt"
      Dbox.pull(@local)
      File.exists?("#{@local}/hello.txt").should be_false
    end
  end

  describe "#push" do
    it "should fail if the local dir is missing" do
      expect { Dbox.push(@local) }.to raise_error(Dbox::MissingDatabase)
    end

    it "should be able to push" do
      Dbox.create(@remote, @local)
      expect { Dbox.push(@local) }.to_not raise_error
    end

    it "should be able to push from inside the dir" do
      Dbox.create(@remote, @local)
      expect { Dbox.push(@local) }.to_not raise_error
    end

    it "should be able to push new file" do
      Dbox.create(@remote, @local)
      touch File.join(@local, "foo.txt")
      expect { Dbox.push(@local) }.to_not raise_error
    end

    it "should create the remote dir if it is missing" do
      Dbox.create(@remote, @local)
      touch File.join(@local, "foo.txt")
      @new_name = randname()
      @new_remote = File.join(REMOTE_TEST_PATH, @new_name)
      modify_dbfile {|s| s.sub(/^remote_path: \/.*$/, "remote_path: #{@new_remote}") }
      expect { Dbox.push(@local) }.to_not raise_error
    end
  end
end
