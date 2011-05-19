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

    def self.pull(local_path)
      load(local_path).pull
    end

    def self.push(local_path)
      load(local_path).push
    end

    def self.move(new_remote_path, local_path)
      load(local_path).move(new_remote_path)
    end

    def self.exists?(local_path)
      File.exists?(db_file(local_path))
    end

    def self.load(local_path)
      if exists?(local_path)
        db = File.open(db_file(local_path), "r") {|f| YAML::load(f.read) }
        db.local_path = local_path
        db
      else
        raise MissingDatabase, "No DB file found in #{local_path}"
      end
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
      @root.pull
    end

    def push
      @root.push
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
        raise(BadPath, "Bad path (#{remote_path} != #{res["path"]})") unless remote_path == res["path"]
        raise(RuntimeError, "Mode on #{@path} changed between file and dir -- not supported yet") unless dir? == res["is_dir"]
        last_modified_at = @modified_at
        @modified_at = parse_time(res["modified"])
        if res["revision"]
          @revision = res["revision"]
        else
          @revision = -1 if @modified_at != last_modified_at
        end
        log.debug "updated modification info on #{path.inspect}: r#{@revision}, #{@modified_at}"
      end

      def smart_new(res)
        if res["is_dir"]
          DropboxDir.new(@db, res)
        else
          DropboxFile.new(@db, res)
        end
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

      def create(direction)
        case direction
        when :down
          create_local
        when :up
          create_remote
        end
      end

      def update(direction)
        case direction
        when :down
          update_local
        when :up
          update_remote
        end
      end

      def delete(direction)
        case direction
        when :down
          delete_local
        when :up
          delete_remote
        end
      end

      def create_local; raise RuntimeError, "Not implemented"; end
      def delete_local; raise RuntimeError, "Not implemented"; end
      def update_local; raise RuntimeError, "Not implemented"; end

      def create_remote; raise RuntimeError, "Not implemented"; end
      def delete_remote; raise RuntimeError, "Not implemented"; end
      def update_remote; raise RuntimeError, "Not implemented"; end

      def modified?(res)
        out = !(@revision == res["revision"] && @modified_at == parse_time(res["modified"]))
        log.debug "#{path}.modified? r#{@revision} =? r#{res["revision"]}, #{@modified_at} =? #{parse_time(res["modified"])} => #{out}"
        out
      end

      def parse_time(t)
        case t
        when Time
          t
        when String
          Time.parse(t)
        end
      end

      def update_file_timestamp
        File.utime(Time.now, @modified_at, local_path)
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

      def pull
        # calculate changes on this dir
        res = api.metadata(remote_path)
        changes = calculate_changes(res)

        # execute changes on this dir
        changelist = execute_changes(changes, :down)

        # recur on subdirs, expanding changelist as we go
        changelist = subdirs.inject(changelist) {|c, d| merge_changelists(c, d.pull) }

        # only update the modification info on the directory once all descendants are updated
        update_modification_info(res)

        # return changes
        @db.save
        changelist
      end

      def push
        # calculate changes on this dir
        res = gather_local_info(@path)
        changes = calculate_changes(res)

        # execute changes on this dir
        changelist = execute_changes(changes, :up)

        # recur on subdirs, expanding changelist as we go
        changelist = subdirs.inject(changelist) {|c, d| merge_changelists(c, d.push) }

        # only update the modification info on the directory once all descendants are updated
        update_modification_info(res)

        # return changes
        @db.save
        changelist
      end

      def calculate_changes(res)
        raise(ArgumentError, "Not a directory: #{res.inspect}") unless res["is_dir"]

        if @contents_hash && res["hash"] && @contents_hash == res["hash"]
          # dir hash hasn't changed -- no need to calculate changes
          []
        elsif res["contents"]
          # dir has changed -- calculate changes on contents
          out = []
          got_paths = []

          remove_dotfiles(res["contents"]).each do |c|
            p = @db.remote_to_relative_path(c["path"])
            c["rel_path"] = p
            got_paths << p

            if @contents.has_key?(p)
              # only update file if it's been modified
              if @contents[p].modified?(c)
                out << [:update, c]
              end
            else
              out << [:create, c]
            end
          end
          out += (@contents.keys.sort - got_paths.sort).map {|p| [:delete, { "rel_path" => p }] }
          out
        else
          raise(RuntimeError, "Trying to calculate dir changes without any contents")
        end
      end

      def execute_changes(changes, direction)
        log.debug "executing changes: #{changes.inspect}"
        changelist = { :created => [], :deleted => [], :updated => [] }
        changes.each do |op, c|
          case op
          when :create
            e = smart_new(c)
            e.create(direction)
            @contents[e.path] = e
            changelist[:created] << e.path
          when :update
            e = @contents[c["rel_path"]]
            e.update_modification_info(c) if direction == :down
            e.update(direction)
            changelist[:updated] << e.path
          when :delete
            e = @contents[c["rel_path"]]
            e.delete(direction)
            @contents.delete(e.path)
            changelist[:deleted] << e.path
          else
            raise(RuntimeError, "Unknown operation type: #{op}")
          end
          @db.save
        end
        changelist.keys.each {|k| changelist[k].sort! }
        changelist
      end

      def merge_changelists(old, new)
        old.merge(new) {|k, v1, v2| (v1 + v2).sort }
      end

      def gather_local_info(rel, list_contents=true)
        full = @db.relative_to_local_path(rel)
        remote = @db.relative_to_remote_path(rel)

        attrs = {
          "path" => remote,
          "is_dir" => File.directory?(full),
          "modified" => File.mtime(full),
          "revision" => @contents[rel] ? @contents[rel].revision : nil
        }

        if attrs["is_dir"] && list_contents
          contents = Dir.entries(full).reject {|s| s == "." || s == ".." }
          attrs["contents"] = contents.map do |s|
            p = File.join(full, s)
            r = @db.local_to_relative_path(p)
            gather_local_info(r, false)
          end
        end

        attrs
      end

      def remove_dotfiles(contents)
        contents.reject {|c| File.basename(c["path"]).start_with?(".") }
      end

      def dir?
        true
      end

      def create_local
        log.info "Creating #{local_path}"
        saving_parent_timestamp do
          FileUtils.mkdir_p(local_path)
          update_file_timestamp
        end
      end

      def delete_local
        log.info "Deleting #{local_path}"
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
        puts "#{path} (v#{@revision}, #{@modified_at})"
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
          api.put_file(remote_path, f)
        end
        force_metadata_update_from_server
      end
    end
  end
end
