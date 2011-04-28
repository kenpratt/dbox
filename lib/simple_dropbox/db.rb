require "yaml"
require "fileutils"
require "time"

module DropboxSync
  class Db
    def self.bootstrap
      case res = API.metadata(REMOTE_PATH)
      when Hash
        # dir is there, create Db
        new(res)
      when Net::HTTPNotFound
        # create remote dir and try again
        API.create_dir(REMOTE_PATH)
        res = API.metadata(REMOTE_PATH)
        new(res) if res.kind_of?(Hash)
      else
        raise "Bootstrap failed: unknown result #{res.inspect}"
      end
    end

    def self.load
      if File.exists?(DB_FILE)
        File.open(DB_FILE, "r") {|f| YAML::load(f.read) }
      else
        self.bootstrap
      end
    end

    # IMPORTANT: DropboxDb.new is private. Please use DropboxDb.load as the entry point.
    private_class_method :new
    def initialize(res)
      @root = DropboxDir.new(res)
      @root.update_file_timestamp
    end

    def save
      Db.saving_timestamp(LOCAL_PATH) do
        File.open(DB_FILE, "w") {|f| f << YAML::dump(self) }
      end
    end

    def pull
      @root.pull
    end

    def push
      @root.push
    end

    def self.saving_timestamp(path)
      mtime = File.mtime(path)
      yield
      File.utime(Time.now, mtime, path)
    end

    class DropboxBlob
      attr_reader :path, :revision, :modified_at

      def initialize(res)
        @path = res["path"]
        update_modification_info(res)
      end

      def update_modification_info(res)
        last_modified_at = @modified_at
        @modified_at = case t = res["modified"]
                       when Time
                         t
                       when String
                         Time.parse(t)
                       end
        if res.has_key?("revision")
          @revision = res["revision"]
        else
          @revision = -1 if @modified_at != last_modified_at
        end
      end

      def self.smart_new(res)
        if res["is_dir"]
          DropboxDir.new(res)
        else
          DropboxFile.new(res)
        end
      end

      def update(res)
        raise "bad path" unless @path == res["path"]
        raise "mode on #{@path} changed between file and dir -- not supported yet" unless dir? == res["is_dir"] # TODO handle change from dir to file or vice versa?
        update_modification_info(res)
      end

      def rel_path
        path.sub(/^#{REMOTE_PATH}\/?/, "")
      end

      def self.filepath(rel_path)
        File.join(LOCAL_PATH, rel_path)
      end

      def self.remote_path(rel)
        case rel
        when ""
          REMOTE_PATH
        else
          File.join(REMOTE_PATH, rel)
        end
      end

      def filepath
        self.class.filepath(rel_path)
      end

      def dir?
        raise "not implemented"
      end

      def create_local; raise "not implemented"; end
      def delete_local; raise "not implemented"; end
      def update_local; raise "not implemented"; end

      def create_remote; raise "not implemented"; end
      def delete_remote; raise "not implemented"; end
      def update_remote; raise "not implemented"; end

      def modified?(last)
        !(revision == last.revision && modified_at == last.modified_at)
      end

      def update_file_timestamp
        File.utime(Time.now, modified_at, filepath)
      end

      def saving_parent_timestamp(&proc)
        parent = File.dirname(filepath)
        Db.saving_timestamp(parent, &proc)
      end
    end

    class DropboxDir < DropboxBlob
      attr_reader :contents_hash, :contents

      def initialize(res)
        @contents_hash = nil
        @contents = {}
        super(res)
      end

      def update(res)
        raise "not a directory" unless res["is_dir"]
        super(res)
        @contents_hash = res["hash"] if res.has_key?("hash")
        if res.has_key?("contents")
          old_contents = @contents
          new_contents_arr = remove_dotfiles(res["contents"]).map do |c|
            if last_entry = old_contents[c["path"]]
              new_entry = last_entry.clone
              last_entry.freeze
              new_entry.update(c)
              [c["path"], new_entry]
            else
              [c["path"], DropboxBlob.smart_new(c)]
            end
          end
          @contents = Hash[new_contents_arr]
        end
      end

      def remove_dotfiles(contents)
        contents.reject {|c| File.basename(c["path"]).start_with?(".") }
      end

      def pull
        prev = self.clone
        prev.freeze
        puts "[db] pulling #{path}"
        res = API.metadata(path)
        update(res)
        if contents_hash != prev.contents_hash
          reconcile(prev, :down)
        end
        subdirs.each {|d| d.pull }
      end

      def push
        prev = self.clone
        prev.freeze
        puts "[db] pushing #{path}"
        res = gather_info(rel_path)
        update(res)
        reconcile(prev, :up)
        subdirs.each {|d| d.push }
      end

      def reconcile(prev, direction)
        old_paths = prev.contents.keys
        new_paths = contents.keys

        deleted_paths = old_paths - new_paths

        created_paths = new_paths - old_paths

        kept_paths = old_paths & new_paths
        stale_paths = kept_paths.select {|p| contents[p].modified?(prev.contents[p]) }

        case direction
        when :down
          deleted_paths.each {|p| prev.contents[p].delete_local }
          created_paths.each {|p| contents[p].create_local }
          stale_paths.each {|p| contents[p].update_local }
        when :up
          deleted_paths.each {|p| prev.contents[p].delete_remote }
          created_paths.each {|p| contents[p].create_remote }
          stale_paths.each {|p| contents[p].update_remote }
        else
          raise "Invalid direction: #{direction.inspect}"
        end
      end

      def gather_info(rel, list_contents=true)
        full = self.class.filepath(rel)
        attrs = {
          "path" => self.class.remote_path(rel),
          "is_dir" => File.directory?(full),
          "modified" => File.mtime(full)
        }

        if attrs["is_dir"] && list_contents
          contents = Dir.chdir(full) { Dir["*"] }
          attrs["contents"] = contents.map do |f|
            gather_info(File.join(rel, f), false)
          end
        end

        attrs
      end

      def dir?
        true
      end

      def create_local
        puts "[fs] creating dir #{filepath}"
        saving_parent_timestamp do
          FileUtils.mkdir_p(filepath)
          update_file_timestamp
        end
      end

      def delete_local
        puts "[fs] deleting dir #{filepath}"
        saving_parent_timestamp do
          FileUtils.rm_r(filepath)
        end
      end

      def update_local
        puts "[fs] updating dir #{filepath}"
        update_file_timestamp
      end

      def create_remote
        API.create_dir(path)
      end

      def delete_remote
        API.delete_dir(path)
      end

      def update_remote
        # do nothing
      end

      def subdirs
        @contents.values.select {|c| c.dir? }
      end

      def print
        puts
        puts "#{path} (v#{revision}, #{modified_at})"
        contents.each do |path, c|
          puts "  #{c.path} (v#{c.revision}, #{c.modified_at})"
        end
        puts
      end
    end

    class DropboxFile < DropboxBlob
      def dir?
        false
      end

      def create_local
        puts "[fs] creating file #{filepath}"
        saving_parent_timestamp do
          download
          update_file_timestamp
        end
      end

      def delete_local
        puts "[fs] deleting file #{filepath}"
        saving_parent_timestamp do
          FileUtils.rm_rf(filepath)
        end
      end

      def update_local
        puts "[fs] updating file #{filepath}"
        download
        update_file_timestamp
      end

      def create_remote
        upload
      end

      def delete_remote
        API.delete_file(path)
      end

      def update_remote
        upload
      end

      def download
        res = API.get_file(path)

        File.open(filepath, "w") do |f|
          f << res
        end
        update_file_timestamp
      end

      def upload
        File.open(filepath) do |f|
          res = API.put_file(path, f)
        end
      end
    end
  end
end
