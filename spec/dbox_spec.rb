# encoding: utf-8

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
      Dbox.create(@remote, @local).should eql(:created => [], :deleted => [], :updated => [""], :failed => [])
      @local.should exist
    end

    it "creates the remote directory" do
      Dbox.create(@remote, @local).should eql(:created => [], :deleted => [], :updated => [""], :failed => [])
      ensure_remote_exists(@remote)
    end

    it "should fail if the remote already exists" do
      Dbox.create(@remote, @local)
      rm_rf @local
      expect { Dbox.create(@remote, @local) }.to raise_error(Dbox::RemoteAlreadyExists)
      @local.should_not exist
    end
  end

  describe "#clone" do
    it "creates the local directory" do
      Dbox.create(@remote, @local)
      rm_rf @local
      @local.should_not exist
      Dbox.clone(@remote, @local).should eql(:created => [], :deleted => [], :updated => [""], :failed => [])
      @local.should exist
    end

    it "should fail if the remote does not exist" do
      expect { Dbox.clone(@remote, @local) }.to raise_error(Dbox::RemoteMissing)
      @local.should_not exist
    end
  end

  describe "#pull" do
    it "should fail if the local dir is missing" do
      expect { Dbox.pull(@local) }.to raise_error(Dbox::DatabaseError)
    end

    it "should fail if the remote dir is missing" do
      Dbox.create(@remote, @local)
      db = Dbox::Database.load(@local)
      db.update_metadata(:remote_path => "/" + randname())
      expect { Dbox.pull(@local) }.to raise_error(Dbox::RemoteMissing)
    end

    it "should be able to pull" do
      Dbox.create(@remote, @local)
      Dbox.pull(@local).should eql(:created => [], :deleted => [], :updated => [], :failed => [])
    end

    it "should be able to pull changes" do
      Dbox.create(@remote, @local)
      "#{@local}/hello.txt".should_not exist

      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)
      make_file "#{@alternate}/hello.txt"
      Dbox.push(@alternate).should eql(:created => ["hello.txt"], :deleted => [], :updated => [], :failed => [])

      Dbox.pull(@local).should eql(:created => ["hello.txt"], :deleted => [], :updated => [""], :failed => [])
      "#{@local}/hello.txt".should exist
    end

    it "should be able to pull after deleting a file and not have the file re-created" do
      Dbox.create(@remote, @local)
      make_file "#{@local}/hello.txt"
      Dbox.push(@local).should eql(:created => ["hello.txt"], :deleted => [], :updated => [], :failed => [])
      rm "#{@local}/hello.txt"
      Dbox.pull(@local).should eql(:created => [], :deleted => [], :updated => [""], :failed => [])
      "#{@local}/hello.txt".should_not exist
    end

    it "should handle a complex set of changes" do
      Dbox.create(@remote, @local)

      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)

      Dbox.pull(@local).should eql(:created => [], :deleted => [], :updated => [], :failed => [])

      make_file "#{@alternate}/foo.txt"
      make_file "#{@alternate}/bar.txt"
      make_file "#{@alternate}/baz.txt"
      Dbox.push(@alternate).should eql(:created => ["bar.txt", "baz.txt", "foo.txt"], :deleted => [], :updated => [], :failed => [])
      Dbox.pull(@alternate).should eql(:created => [], :deleted => [], :updated => [""], :failed => [])
      Dbox.pull(@alternate).should eql(:created => [], :deleted => [], :updated => [], :failed => [])

      Dbox.pull(@local).should eql(:created => ["bar.txt", "baz.txt", "foo.txt"], :deleted => [], :updated => [""], :failed => [])
      Dbox.pull(@local).should eql(:created => [], :deleted => [], :updated => [], :failed => [])

      mkdir "#{@alternate}/subdir"
      make_file "#{@alternate}/subdir/one.txt"
      rm "#{@alternate}/foo.txt"
      make_file "#{@alternate}/baz.txt"
      Dbox.push(@alternate).should eql(:created => ["subdir", "subdir/one.txt"], :deleted => ["foo.txt"], :updated => ["baz.txt"], :failed => [])
      Dbox.pull(@alternate).should eql(:created => [], :deleted => [], :updated => ["", "subdir"], :failed => [])
      Dbox.pull(@alternate).should eql(:created => [], :deleted => [], :updated => [], :failed => [])

      Dbox.pull(@local).should eql(:created => ["subdir", "subdir/one.txt"], :deleted => ["foo.txt"], :updated => ["", "baz.txt"], :failed => [])
      Dbox.pull(@local).should eql(:created => [], :deleted => [], :updated => [], :failed => [])
    end

    it "should be able to download a bunch of files at the same time" do
      Dbox.create(@remote, @local)
      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)

      # generate 20 x 100kB files
      20.times do
        make_file "#{@alternate}/#{randname}.txt", 100
      end

      Dbox.push(@alternate)

      res = Dbox.pull(@local)
      res[:deleted].should eql([])
      res[:updated].should eql([""])
      res[:failed].should eql([])
      res[:created].size.should eql(20)
    end

    it "should be able to pull a series of updates to the same file" do
      Dbox.create(@remote, @local)
      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)

      make_file "#{@local}/hello.txt"
      Dbox.push(@local)
      Dbox.pull(@alternate).should eql(:created => ["hello.txt"], :deleted => [], :updated => [""], :failed => [])
      make_file "#{@local}/hello.txt"
      Dbox.push(@local)
      Dbox.pull(@alternate).should eql(:created => [], :deleted => [], :updated => ["", "hello.txt"], :failed => [])
      make_file "#{@local}/hello.txt"
      Dbox.push(@local)
      Dbox.pull(@alternate).should eql(:created => [], :deleted => [], :updated => ["", "hello.txt"], :failed => [])
    end

    it "should handle conflicting pulls of new files gracefully" do
      Dbox.create(@remote, @local)
      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)

      make_file "#{@local}/hello.txt"
      Dbox.push(@local)

      make_file "#{@alternate}/hello.txt"
      Dbox.pull(@alternate).should eql(:created => ["hello.txt"], :deleted => [], :updated => [""], :conflicts => [{:original => "hello.txt", :renamed => "hello (1).txt"}], :failed => [])
    end

    it "should handle conflicting pulls of updated files gracefully" do
      Dbox.create(@remote, @local)
      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)

      make_file "#{@local}/hello.txt"
      Dbox.push(@local)
      Dbox.pull(@alternate).should eql(:created => ["hello.txt"], :deleted => [], :updated => [""], :failed => [])

      make_file "#{@local}/hello.txt"
      Dbox.push(@local)

      make_file "#{@alternate}/hello.txt"
      Dbox.pull(@alternate).should eql(:created => [], :deleted => [], :updated => ["", "hello.txt"], :conflicts => [{:original => "hello.txt", :renamed => "hello (1).txt"}], :failed => [])
    end

    it "should deal with all sorts of weird filenames when renaming due to conflicts on pull" do
      Dbox.create(@remote, @local)
      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)

      make_file "#{@local}/hello.txt"
      make_file "#{@local}/hello (1).txt"
      make_file "#{@local}/goodbye.txt"
      Dbox.push(@local)

      make_file "#{@alternate}/hello.txt"
      make_file "#{@alternate}/hello (1).txt"
      make_file "#{@alternate}/hello (3).txt"
      make_file "#{@alternate}/hello (4).txt"
      make_file "#{@alternate}/hello (test).txt"
      make_file "#{@alternate}/goodbye.txt"
      make_file "#{@alternate}/goodbye (1).txt"
      make_file "#{@alternate}/goodbye (2).txt"
      make_file "#{@alternate}/goodbye (3).txt"
      make_file "#{@alternate}/goodbye ().txt"

      # there's a race condition, so the output could be one of two things
      res = Dbox.pull(@alternate)
      res[:created].should eql(["goodbye.txt", "hello (1).txt", "hello.txt"])
      res[:updated].should eql([""])
      res[:deleted].should eql([])
      res[:failed].should eql([])
      c = (res[:conflicts] == [{:original => "goodbye.txt", :renamed => "goodbye (4).txt"}, {:original => "hello (1).txt", :renamed => "hello (5).txt"}, {:original => "hello.txt", :renamed => "hello (2).txt"}]) ||
        (res[:conflicts] == [{:original => "goodbye.txt", :renamed => "goodbye (4).txt"}, {:original => "hello (1).txt", :renamed => "hello (2).txt"}, {:original => "hello.txt", :renamed => "hello (5).txt"}])
      c.should be_true
    end
  end

  describe "#clone_or_pull" do
    it "creates the local directory" do
      Dbox.create(@remote, @local)
      rm_rf @local
      @local.should_not exist
      Dbox.clone_or_pull(@remote, @local).should eql(:created => [], :deleted => [], :updated => [""], :failed => [])
      @local.should exist
    end

    it "should fail if the remote does not exist" do
      expect { Dbox.clone_or_pull(@remote, @local) }.to raise_error(Dbox::RemoteMissing)
      @local.should_not exist
    end

    it "shold be able to pull changes on existing repo" do
      Dbox.create(@remote, @local)
      @local.should exist
      Dbox.clone_or_pull(@remote, @local).should eql(:created => [], :deleted => [], :updated => [], :failed => [])
      @local.should exist
    end
  end

  describe "#push" do
    it "should fail if the local dir is missing" do
      expect { Dbox.push(@local) }.to raise_error(Dbox::DatabaseError)
    end

    it "should be able to push" do
      Dbox.create(@remote, @local)
      Dbox.push(@local).should eql(:created => [], :deleted => [], :updated => [], :failed => [])
    end

    it "should be able to push a new file" do
      Dbox.create(@remote, @local)
      make_file "#{@local}/foo.txt"
      Dbox.push(@local).should eql(:created => ["foo.txt"], :deleted => [], :updated => [], :failed => [])
    end

    it "should be able to push a new dir" do
      Dbox.create(@remote, @local)
      mkdir "#{@local}/subdir"
      Dbox.push(@local).should eql(:created => ["subdir"], :deleted => [], :updated => [], :failed => [])
    end

    it "should be able to push a new dir with a file in it" do
      Dbox.create(@remote, @local)
      mkdir "#{@local}/subdir"
      make_file "#{@local}/subdir/foo.txt"
      Dbox.push(@local).should eql(:created => ["subdir", "subdir/foo.txt"], :deleted => [], :updated => [], :failed => [])
    end

    it "should be able to push a new file in an existing dir" do
      Dbox.create(@remote, @local)
      mkdir "#{@local}/subdir"
      Dbox.push(@local)
      make_file "#{@local}/subdir/foo.txt"
      Dbox.push(@local).should eql(:created => ["subdir/foo.txt"], :deleted => [], :updated => [], :failed => [])
    end

    it "should create the remote dir if it is missing" do
      Dbox.create(@remote, @local)
      make_file "#{@local}/foo.txt"
      @new_name = randname()
      @new_remote = File.join(REMOTE_TEST_PATH, @new_name)
      db = Dbox::Database.load(@local)
      db.update_metadata(:remote_path => @new_remote)
      Dbox.push(@local).should eql(:created => ["foo.txt"], :deleted => [], :updated => [], :failed => [])
    end

    it "should not re-download the file after creating" do
      Dbox.create(@remote, @local)
      make_file "#{@local}/foo.txt"
      Dbox.push(@local).should eql(:created => ["foo.txt"], :deleted => [], :updated => [], :failed => [])
      Dbox.pull(@local).should eql(:created => [], :deleted => [], :updated => [""], :failed => [])
    end

    it "should not re-download the file after updating" do
      Dbox.create(@remote, @local)
      make_file "#{@local}/foo.txt"
      Dbox.push(@local).should eql(:created => ["foo.txt"], :deleted => [], :updated => [], :failed => [])
      sleep 1 # need to wait for timestamp to change before writing same file
      make_file "#{@local}/foo.txt"
      Dbox.push(@local).should eql(:created => [], :deleted => [], :updated => ["foo.txt"], :failed => [])
      Dbox.pull(@local).should eql(:created => [], :deleted => [], :updated => [""], :failed => [])
    end

    it "should not re-download the dir after creating" do
      Dbox.create(@remote, @local)
      mkdir "#{@local}/subdir"
      Dbox.push(@local).should eql(:created => ["subdir"], :deleted => [], :updated => [], :failed => [])
      Dbox.pull(@local).should eql(:created => [], :deleted => [], :updated => [""], :failed => [])
    end

    it "should handle a complex set of changes" do
      Dbox.create(@remote, @local)
      make_file "#{@local}/foo.txt"
      make_file "#{@local}/bar.txt"
      make_file "#{@local}/baz.txt"
      Dbox.push(@local).should eql(:created => ["bar.txt", "baz.txt", "foo.txt"], :deleted => [], :updated => [], :failed => [])
      sleep 1 # need to wait for timestamp to change before writing same file
      mkdir "#{@local}/subdir"
      make_file "#{@local}/subdir/one.txt"
      rm "#{@local}/foo.txt"
      make_file "#{@local}/baz.txt"
      Dbox.push(@local).should eql(:created => ["subdir", "subdir/one.txt"], :deleted => ["foo.txt"], :updated => ["baz.txt"], :failed => [])
      Dbox.pull(@local).should eql(:created => [], :deleted => [], :updated => ["", "subdir"], :failed => [])
    end

    it "should be able to handle crazy filenames" do
      Dbox.create(@remote, @local)
      crazy_name1 = '=+!@#  $%^&*()[]{}<>_-|:?,\'~".txt'
      crazy_name2 = '[ˈdɔʏtʃ].txt'
      make_file "#{@local}/#{crazy_name1}"
      make_file "#{@local}/#{crazy_name2}"
      Dbox.push(@local).should eql(:created => [crazy_name1, crazy_name2], :deleted => [], :updated => [], :failed => [])
      rm_rf @local
      Dbox.clone(@remote, @local).should eql(:created => [crazy_name1, crazy_name2], :deleted => [], :updated => [""], :failed => [])
    end

    it "should be able to handle crazy directory names" do
      Dbox.create(@remote, @local)
      crazy_name1 = "Day[J] #42"
      mkdir File.join(@local, crazy_name1)
      make_file File.join(@local, crazy_name1, "foo.txt")
      Dbox.push(@local).should eql(:created => [crazy_name1, File.join(crazy_name1, "foo.txt")], :deleted => [], :updated => [], :failed => [])
      rm_rf @local
      Dbox.clone(@remote, @local).should eql(:created => [crazy_name1, File.join(crazy_name1, "foo.txt")], :deleted => [], :updated => [""], :failed => [])
    end

    it "should be able to upload a bunch of files at the same time" do
      Dbox.create(@remote, @local)

      # generate 20 x 100kB files
      20.times do
        make_file "#{@local}/#{randname}.txt", 100
      end

      res = Dbox.push(@local)
      res[:deleted].should eql([])
      res[:updated].should eql([])
      res[:failed].should eql([])
      res[:created].size.should eql(20)
    end

    it "should be able to push a series of updates to the same file" do
      Dbox.create(@remote, @local)

      make_file "#{@local}/hello.txt"
      Dbox.push(@local).should eql(:created => ["hello.txt"], :deleted => [], :updated => [], :failed => [])
      make_file "#{@local}/hello.txt"
      Dbox.push(@local).should eql(:created => [], :deleted => [], :updated => ["hello.txt"], :failed => [])
      make_file "#{@local}/hello.txt"
      Dbox.push(@local).should eql(:created => [], :deleted => [], :updated => ["hello.txt"], :failed => [])
    end

    it "should handle conflicting pushes of new files gracefully" do
      Dbox.create(@remote, @local)

      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)

      make_file "#{@local}/hello.txt"
      Dbox.push(@local).should eql(:created => ["hello.txt"], :deleted => [], :updated => [], :failed => [])

      make_file "#{@alternate}/hello.txt"
      Dbox.push(@alternate).should eql(:created => [], :deleted => [], :updated => [], :conflicts => [{:original => "hello.txt", :renamed => "hello (1).txt"}], :failed => [])
    end

    it "should handle conflicting pushes of updated files gracefully" do
      Dbox.create(@remote, @local)
      make_file "#{@local}/hello.txt"
      Dbox.push(@local)

      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)

      make_file "#{@local}/hello.txt"
      Dbox.push(@local).should eql(:created => [], :deleted => [], :updated => ["hello.txt"], :failed => [])

      make_file "#{@alternate}/hello.txt"
      res = Dbox.push(@alternate)
      res[:created].should eql([])
      res[:updated].should eql([])
      res[:deleted].should eql([])
      res[:failed].should eql([])
      res[:conflicts].size.should eql(1)
      res[:conflicts][0][:original].should eql("hello.txt")
      res[:conflicts][0][:renamed].should match(/hello \(.* conflicted copy\).txt/)
    end
  end

  describe "#sync" do
    it "should fail if the local dir is missing" do
      expect { Dbox.sync(@local) }.to raise_error(Dbox::DatabaseError)
    end

    it "should be able to sync basic changes" do
      Dbox.create(@remote, @local)
      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)

      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                   :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
      Dbox.sync(@alternate).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                       :push => { :created => [], :deleted => [], :updated => [], :failed => [] })

      make_file "#{@local}/hello.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                   :push => { :created => ["hello.txt"], :deleted => [], :updated => [], :failed => [] })
      Dbox.sync(@alternate).should eql(:pull => { :created => ["hello.txt"], :deleted => [], :updated => [""], :failed => [] },
                                       :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
    end

    it "should be able to sync complex changes" do
      Dbox.create(@remote, @local)
      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)

      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                   :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
      Dbox.sync(@alternate).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                       :push => { :created => [], :deleted => [], :updated => [], :failed => [] })

      make_file "#{@local}/hello.txt"
      make_file "#{@local}/goodbye.txt"
      make_file "#{@local}/so_long.txt"
      make_file "#{@alternate}/hello.txt"
      make_file "#{@alternate}/farewell.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                   :push => { :created => ["goodbye.txt", "hello.txt", "so_long.txt"], :deleted => [], :updated => [], :failed => [] })
      Dbox.sync(@alternate).should eql(:pull => { :created => ["goodbye.txt", "hello.txt", "so_long.txt"], :deleted => [], :updated => [""], :failed => [], :conflicts => [{ :renamed => "hello (1).txt", :original => "hello.txt" }] },
                                       :push => { :created => ["farewell.txt", "hello (1).txt"], :deleted => [], :updated => [], :failed => [] })

      make_file "#{@alternate}/farewell.txt"
      make_file "#{@alternate}/goodbye.txt"
      make_file "#{@alternate}/au_revoir.txt"
      Dbox.sync(@alternate).should eql(:pull => { :created => [], :deleted => [], :updated => [""], :failed => [] },
                                       :push => { :created => ["au_revoir.txt"], :deleted => [], :updated => ["farewell.txt", "goodbye.txt"], :failed => [] })
      Dbox.sync(@local).should eql(:pull => { :created => ["au_revoir.txt", "farewell.txt", "hello (1).txt"], :deleted => [], :updated => ["", "goodbye.txt"], :failed => [] },
                                   :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
    end

    it "should be able to handle a file that has changed case" do
      Dbox.create(@remote, @local)
      make_file "#{@local}/hello.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                   :push => { :created => ["hello.txt"], :deleted => [], :updated => [], :failed => [] })
      rename_file "#{@local}/hello.txt", "#{@local}/HELLO.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [""], :failed => [] },
                                   :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
    end

    it "should be able to handle a file that has changed case remotely" do
      Dbox.create(@remote, @local)
      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)
      make_file "#{@local}/hello.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                   :push => { :created => ["hello.txt"], :deleted => [], :updated => [], :failed => [] })
      Dbox.sync(@alternate).should eql(:pull => { :created => ["hello.txt"], :deleted => [], :updated => [""], :failed => [] },
                                       :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
      rename_file "#{@local}/hello.txt", "#{@local}/HELLO.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [""], :failed => [] },
                                   :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
      Dbox.sync(@alternate).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                       :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
    end

    it "should be able to handle a folder that has changed case" do
      Dbox.create(@remote, @local)
      mkdir "#{@local}/foo"
      make_file "#{@local}/foo/hello.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                   :push => { :created => ["foo", "foo/hello.txt"], :deleted => [], :updated => [], :failed => [] })
      rename_file "#{@local}/foo", "#{@local}/FOO"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => ["", "foo"], :failed => [] },
                                   :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
      make_file "#{@local}/FOO/hello2.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                   :push => { :created => ["FOO/hello2.txt"], :deleted => [], :updated => [], :failed => [] })
    end

    it "should be able to handle a folder that has changed case remotely" do
      Dbox.create(@remote, @local)
      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)
      mkdir "#{@local}/foo"
      make_file "#{@local}/foo/hello.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                   :push => { :created => ["foo", "foo/hello.txt"], :deleted => [], :updated => [], :failed => [] })
      Dbox.sync(@alternate).should eql(:pull => { :created => ["foo", "foo/hello.txt"], :deleted => [], :updated => [""], :failed => [] },
                                       :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
      rename_file "#{@local}/foo", "#{@local}/FOO"
      make_file "#{@local}/FOO/hello2.txt"
      make_file "#{@alternate}/foo/hello3.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => ["", "foo"], :failed => [] },
                                   :push => { :created => ["FOO/hello2.txt"], :deleted => [], :updated => [], :failed => [] })
      Dbox.sync(@alternate).should eql(:pull => { :created => ["foo/hello2.txt"], :deleted => [], :updated => ["foo"], :failed => [] },
                                       :push => { :created => ["foo/hello3.txt"], :deleted => [], :updated => [], :failed => [] })
      Dbox.sync(@local).should eql(:pull => { :created => ["foo/hello3.txt"], :deleted => [], :updated => ["foo"], :failed => [] },
                                   :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
    end

    it "should be able to handle creating a new file of a different case from a deleted file" do
      Dbox.create(@remote, @local)
      mkdir "#{@local}/foo"
      make_file "#{@local}/foo/hello.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                   :push => { :created => ["foo", "foo/hello.txt"], :deleted => [], :updated => [], :failed => [] })
      rm_rf "#{@local}/foo"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => ["", "foo"], :failed => [] },
                                   :push => { :created => [], :deleted => ["foo"], :updated => [], :failed => [] })
      mkdir "#{@local}/FOO"
      make_file "#{@local}/FOO/HELLO.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [""], :failed => [] },
                                   :push => { :created => ["FOO", "FOO/HELLO.txt"], :deleted => [], :updated => [], :failed => [] })
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => ["", "FOO"], :failed => [] },
                                   :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
    end

    it "should be able to handle creating a new file of a different case from a deleted file remotely" do
      Dbox.create(@remote, @local)
      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)

      mkdir "#{@local}/foo"
      make_file "#{@local}/foo/hello.txt"
      Dbox.sync(@local).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                   :push => { :created => ["foo", "foo/hello.txt"], :deleted => [], :updated => [], :failed => [] })
      Dbox.sync(@alternate).should eql(:pull => { :created => ["foo", "foo/hello.txt"], :deleted => [], :updated => [""], :failed => [] },
                                       :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
      rm_rf "#{@alternate}/foo"
      Dbox.sync(@alternate).should eql(:pull => { :created => [], :deleted => [], :updated => [], :failed => [] },
                                       :push => { :created => [], :deleted => ["foo"], :updated => [], :failed => [] })
      mkdir "#{@alternate}/FOO"
      make_file "#{@alternate}/FOO/HELLO.txt"
      make_file "#{@alternate}/FOO/HELLO2.txt"
      Dbox.sync(@alternate).should eql(:pull => { :created => [], :deleted => [], :updated => [""], :failed => [] },
                                       :push => { :created => ["FOO", "FOO/HELLO.txt", "FOO/HELLO2.txt"], :deleted => [], :updated => [], :failed => [] })

      rename_file "#{@alternate}/FOO", "#{@alternate}/Foo"
      make_file "#{@alternate}/Foo/Hello3.txt"
      Dbox.sync(@alternate).should eql(:pull => { :created => [], :deleted => [], :updated => ["", "FOO"], :failed => [] },
                                       :push => { :created => ["Foo/Hello3.txt"], :deleted => [], :updated => [], :failed => [] })

      Dbox.sync(@local).should eql(:pull => { :created => ["foo/HELLO2.txt", "foo/Hello3.txt"], :deleted => [], :updated => ["", "FOO", "foo/HELLO.txt"], :failed => [] },
                                   :push => { :created => [], :deleted => [], :updated => [], :failed => [] })
    end
  end

  describe "#move" do
    before(:each) do
      @new_name = randname()
      @new_local = File.join(LOCAL_TEST_PATH, @new_name)
      @new_remote = File.join(REMOTE_TEST_PATH, @new_name)
    end

    it "should fail if the local dir is missing" do
      expect { Dbox.move(@new_remote, @local) }.to raise_error(Dbox::DatabaseError)
    end

    it "should be able to move" do
      Dbox.create(@remote, @local)
      expect { Dbox.move(@new_remote, @local) }.to_not raise_error
      @local.should exist
      expect { Dbox.clone(@new_remote, @new_local) }.to_not raise_error
      @new_local.should exist
    end

    it "should not be able to move to a location that exists" do
      Dbox.create(@remote, @local)
      Dbox.create(@new_remote, @new_local)
      expect { Dbox.move(@new_remote, @local) }.to raise_error(Dbox::RemoteAlreadyExists)
    end
  end

  describe "#exists?" do
    it "should be false if the local dir is missing" do
      Dbox.exists?(@local).should be_false
    end

    it "should be true if the dir exists" do
      Dbox.create(@remote, @local)
      Dbox.exists?(@local).should be_true
    end

    it "should be false if the dir exists but is missing a .dbox.sqlite3 file" do
      Dbox.create(@remote, @local)
      rm "#{@local}/.dbox.sqlite3"
      Dbox.exists?(@local).should be_false
    end
  end

  describe "misc" do
    it "should be able to recreate a dir after deleting it" do
      Dbox.create(@remote, @local)

      @alternate = "#{ALTERNATE_LOCAL_TEST_PATH}/#{@name}"
      Dbox.clone(@remote, @alternate)

      Dbox.pull(@local).should eql(:created => [], :deleted => [], :updated => [], :failed => [])

      mkdir "#{@local}/subdir"
      make_file "#{@local}/subdir/one.txt"
      Dbox.push(@local).should eql(:created => ["subdir", "subdir/one.txt"], :deleted => [], :updated => [], :failed => [])

      Dbox.pull(@alternate).should eql(:created => ["subdir", "subdir/one.txt"], :deleted => [], :updated => [""], :failed => [])

      rm_rf "#{@alternate}/subdir"
      Dbox.push(@alternate).should eql(:created => [], :deleted => ["subdir"], :updated => [], :failed => [])

      Dbox.pull(@local).should eql(:created => [], :deleted => ["subdir"], :updated => [""], :failed => [])

      sleep 1 # need to wait for timestamp to change before writing same file
      mkdir "#{@local}/subdir"
      make_file "#{@local}/subdir/one.txt"
      Dbox.push(@local).should eql(:created => ["subdir", "subdir/one.txt"], :deleted => [], :updated => [], :failed => [])

      Dbox.pull(@alternate).should eql(:created => ["subdir", "subdir/one.txt"], :deleted => [], :updated => [""], :failed => [])
    end
  end

  describe "#delete" do
    it "should delete the remote directory" do
      Dbox.create(@remote, @local)
      rm_rf @local
      Dbox.delete(@remote)
      expect { Dbox.clone(@remote, @local) }.to raise_error(Dbox::RemoteMissing)
    end

    it "should delete the local directory if given" do
      Dbox.create(@remote, @local)
      @local.should exist
      Dbox.delete(@remote, @local)
      @local.should_not exist
      expect { Dbox.clone(@remote, @local) }.to raise_error(Dbox::RemoteMissing)
    end
  end
end
