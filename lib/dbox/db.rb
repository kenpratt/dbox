module Dbox
  class MissingDatabase < RuntimeError; end
  class BadPath < RuntimeError; end

  class DB
    include Loggable

    DB_FILE = ".dropbox.db"

    attr_accessor :local_path

    def self.create(remote_path, local_path)
      api.create_dir(remote_path)
      clone(remote_path, local_path)
    end

    def self.clone(remote_path, local_path)
      log.info "Cloning #{remote_path} into #{local_path}"
      res = api.metadata(remote_path)
      raise(BadPath, "Remote path error") unless remote_path == res["path"]
      db = new(local_path, res)
      db.pull
    end

    def self.load(local_path)
      db_file = db_file(local_path)
      if File.exists?(db_file)
        db = File.open(db_file, "r") {|f| YAML::load(f.read) }
        db.local_path = local_path
        db
      else
        raise MissingDatabase, "No DB file found in #{local_path}"
      end
    end

    def self.pull(local_path)
      load(local_path).pull
    end

    def self.push(local_path)
      load(local_path).push
    end

    def self.move(new_remote_path, local_path)
      load(local_path).move(new_remote_path)
    end

    # IMPORTANT: DropboxDb.new is private. Please use DropboxDb.create, DropboxDb.clone, or DropboxDb.load as the entry point.
    private_class_method :new
    def initialize(local_path, res)
      @local_path = local_path
      @remote_path = res["path"]
      FileUtils.mkdir_p(@local_path)
      @root = DropboxDir.new(self, res)
      save
    end

    def save
      self.class.saving_timestamp(@local_path) do
        File.open(db_file, "w") {|f| f << YAML::dump(self) }
      end
    end

    def pull
      res = @root.pull
      save
      res
    end

    def push
      res = @root.push
      save
      res
    end

    def move(new_remote_path)
      api.move(@remote_path, new_remote_path)
      @remote_path = new_remote_path
      save
    end

    def local_to_relative_path(path)
      if path.include?(@local_path)
        path.sub(@local_path, "").sub(/^\//, "")
      else
        raise BadPath, "Not a local path: #{path}"
      end
    end

    def remote_to_relative_path(path)
      if path.include?(@remote_path)
        path.sub(@remote_path, "").sub(/^\//, "")
      else
        raise BadPath, "Not a remote path: #{path}"
      end
    end

    def relative_to_local_path(path)
      if path.any?
        File.join(@local_path, path)
      else
        @local_path
      end
    end

    def relative_to_remote_path(path)
      if path.any?
        File.join(@remote_path, path)
      else
        @remote_path
      end
    end

    def self.saving_timestamp(path)
      mtime = File.mtime(path)
      yield
      File.utime(Time.now, mtime, path)
    end

    def self.api
      @api ||= API.connect
    end

    def api
      self.class.api
    end

    def self.db_file(local_path)
      File.join(local_path, DB_FILE)
    end

    def db_file
      self.class.db_file(@local_path)
    end

    class DropboxBlob
      include Loggable

      attr_reader :path, :revision, :modified_at

      def initialize(db, res)
        @db = db
        @path = @db.remote_to_relative_path(res["path"])
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

      def smart_new(res)
        if res["is_dir"]
          DropboxDir.new(@db, res)
        else
          DropboxFile.new(@db, res)
        end
      end

      def update(res)
        raise(BadPath, "Bad path (#{remote_path} != #{res["path"]})") unless remote_path == res["path"]
        raise(RuntimeError, "Mode on #{@path} changed between file and dir -- not supported yet") unless dir? == res["is_dir"]
        update_modification_info(res)
      end

      def local_path
        @db.relative_to_local_path(@path)
      end

      def remote_path
        @db.relative_to_remote_path(@path)
      end

      def dir?
        raise RuntimeError, "Not implemented"
      end

      def create_local; raise RuntimeError, "Not implemented"; end
      def delete_local; raise RuntimeError, "Not implemented"; end
      def update_local; raise RuntimeError, "Not implemented"; end

      def create_remote; raise RuntimeError, "Not implemented"; end
      def delete_remote; raise RuntimeError, "Not implemented"; end
      def update_remote; raise RuntimeError, "Not implemented"; end

      def modified?(last)
        !(revision == last.revision && modified_at == last.modified_at)
      end

      def update_file_timestamp
        File.utime(Time.now, modified_at, local_path)
      end

      # this downloads the metadata about this blob from the server and
      # overwrites the metadata & timestamp
      # IMPORTANT: should only be called if you are CERTAIN the file is up to date
      def force_metadata_update_from_server
        res = api.metadata(remote_path)
        update_modification_info(res)
        update_file_timestamp
      end

      def saving_parent_timestamp(&proc)
        parent = File.dirname(local_path)
        DB.saving_timestamp(parent, &proc)
      end

      def api
        @db.api
      end
    end

    class DropboxDir < DropboxBlob
      attr_reader :contents_hash, :contents

      def initialize(db, res)
        @contents_hash = nil
        @contents = {}
        super(db, res)
      end

      def update(res)
        raise(ArgumentError, "Not a directory: #{res.inspect}") unless res["is_dir"]
        super(res)
        @contents_hash = res["hash"] if res.has_key?("hash")
        if res.has_key?("contents")
          old_contents = @contents
          new_contents_arr = remove_dotfiles(res["contents"]).map do |c|
            p = @db.remote_to_relative_path(c["path"])
            if last_entry = old_contents[p]
              new_entry = last_entry.clone
              last_entry.freeze
              new_entry.update(c)
              [new_entry.path, new_entry]
            else
              new_entry = smart_new(c)
              [new_entry.path, new_entry]
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
        res = api.metadata(remote_path)
        update(res)
        if contents_hash != prev.contents_hash
          changes = reconcile(prev, :down)
        else
          changes = { :created => [], :deleted => [], :updated => [] }
        end
        subdirs.inject(changes) {|c, d| merge_changes(c, d.pull) }
      end

      def push
        prev = self.clone
        prev.freeze
        res = gather_info(@path)
        update(res)
        changes = reconcile(prev, :up)
        subdirs.inject(changes) {|c, d| merge_changes(c, d.push) }
      end

      def reconcile(prev, direction)
        old_paths = prev.contents.keys.sort
        new_paths = contents.keys.sort

        deleted_paths = old_paths - new_paths

        created_paths = new_paths - old_paths

        kept_paths = old_paths & new_paths
        stale_paths = kept_paths.select {|p| contents[p].modified?(prev.contents[p]) }

        case direction
        when :down
          deleted_paths.each {|p| prev.contents[p].delete_local }
          created_paths.each {|p| contents[p].create_local }
          stale_paths.each {|p| contents[p].update_local }
          { :created => created_paths, :deleted => deleted_paths, :updated => stale_paths }
        when :up
          deleted_paths.each {|p| prev.contents[p].delete_remote }
          created_paths.each {|p| contents[p].create_remote }
          stale_paths.each {|p| contents[p].update_remote }
          { :created => created_paths, :deleted => deleted_paths, :updated => stale_paths }
        else
          raise(ArgumentError, "Invalid sync direction: #{direction.inspect}")
        end
      end

      def merge_changes(old, new)
        old.merge(new) {|k, v1, v2| v1 + v2 }
      end

      def gather_info(rel, list_contents=true)
        full = @db.relative_to_local_path(rel)
        remote = @db.relative_to_remote_path(rel)

        attrs = {
          "path" => remote,
          "is_dir" => File.directory?(full),
          "modified" => File.mtime(full)
        }

        if attrs["is_dir"] && list_contents
          contents = Dir[File.join(full, "*")]
          attrs["contents"] = contents.map do |f|
            r = @db.local_to_relative_path(f)
            gather_info(r, false)
          end
        end

        attrs
      end

      def dir?
        true
      end

      def create_local
        saving_parent_timestamp do
          FileUtils.mkdir_p(local_path)
          update_file_timestamp
        end
      end

      def delete_local
        log.info "Deleting dir: #{local_path}"
        saving_parent_timestamp do
          FileUtils.rm_r(local_path)
        end
      end

      def update_local
        update_file_timestamp
      end

      def create_remote
        api.create_dir(remote_path)
        force_metadata_update_from_server
      end

      def delete_remote
        api.delete_dir(remote_path)
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
        saving_parent_timestamp do
          download
        end
      end

      def delete_local
        log.info "Deleting file: #{local_path}"
        saving_parent_timestamp do
          FileUtils.rm_rf(local_path)
        end
      end

      def update_local
        download
      end

      def create_remote
        upload
      end

      def delete_remote
        api.delete_file(remote_path)
      end

      def update_remote
        upload
      end

      def download
        res = api.get_file(remote_path)

        File.open(local_path, "w") do |f|
          f << res
        end
        update_file_timestamp
      end

      def upload
        File.open(local_path) do |f|
          res = api.put_file(remote_path, f)
        end
        force_metadata_update_from_server
      end
    end
  end
end
