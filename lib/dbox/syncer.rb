module Dbox
  class Syncer
    MAX_PARALLEL_DBOX_OPS = 5

    include Loggable

    def self.create(remote_path, local_path)
      api.create_dir(remote_path)
      clone(remote_path, local_path)
    end

    def self.clone(remote_path, local_path)
      api.metadata(remote_path) # ensure remote exists
      database = Database.create(remote_path, local_path)
      Pull.new(database, api).execute
    end

    def self.pull(local_path)
      database = Database.load(local_path)
      Pull.new(database, api).execute
    end

    def self.push(local_path)
      database = Database.load(local_path)
      Push.new(database, api).execute
    end

    def self.move(new_remote_path, local_path)
      database = Database.load(local_path)
      api.move(database.metadata[:remote_path], new_remote_path)
      database.update_metadata(:remote_path => new_remote_path)
    end

    def self.api
      @@_api ||= API.connect
    end

    class Operation
      include Loggable

      attr_reader :database

      def initialize(database, api)
        @database = database
        @api = api
      end

      def api
        Thread.current[:api] || @api
      end

      def clone_api_into_current_thread
        Thread.current[:api] = api.clone()
      end

      def metadata
        @_metadata ||= database.metadata
      end

      def local_path
        metadata[:local_path]
      end

      def remote_path
        metadata[:remote_path]
      end

      def local_to_relative_path(path)
        if path.include?(local_path)
          path.sub(local_path, "").sub(/^\//, "")
        else
          raise BadPath, "Not a local path: #{path}"
        end
      end

      def remote_to_relative_path(path)
        if path.include?(remote_path)
          path.sub(remote_path, "").sub(/^\//, "")
        else
          raise BadPath, "Not a remote path: #{path}"
        end
      end

      def relative_to_local_path(path)
        if path && path.length > 0
          File.join(local_path, path)
        else
          local_path
        end
      end

      def relative_to_remote_path(path)
        if path && path.length > 0
          File.join(remote_path, path)
        else
          remote_path
        end
      end

      def remove_dotfiles(contents)
        contents.reject {|c| File.basename(c[:path]).start_with?(".") }
      end

      def current_dir_entries_as_hash(dir)
        if dir[:id]
          out = {}
          database.contents(dir[:id]).each {|e| out[e[:path]] = e }
          out
        else
          {}
        end
      end

      def lookup_id_by_path(path)
        @_ids ||= {}
        @_ids[path] ||= database.find_by_path(path)[:id]
      end

      def time_to_s(t)
        case t
        when Time
          # matches dropbox time format
          t.utc.strftime("%a, %d %b %Y %H:%M:%S +0000")
        when String
          t
        end
      end

      def parse_time(t)
        case t
        when Time
          t
        when String
          Time.parse(t)
        end
      end

      def saving_timestamp(path)
        mtime = File.mtime(path)
        yield
        File.utime(Time.now, mtime, path)
      end

      def saving_parent_timestamp(entry, &proc)
        local_path = relative_to_local_path(entry[:path])
        parent = File.dirname(local_path)
        saving_timestamp(parent, &proc)
      end

      def update_file_timestamp(entry)
        File.utime(Time.now, entry[:modified], relative_to_local_path(entry[:path]))
      end

      def gather_remote_info(entry)
        res = api.metadata(relative_to_remote_path(entry[:path]), entry[:hash])
        case res
        when Hash
          out = process_basic_remote_props(res)
          out[:id] = entry[:id] if entry[:id]
          if res[:contents]
            out[:contents] = remove_dotfiles(res[:contents]).map do |c|
              o = process_basic_remote_props(c)
              o[:parent_id] = entry[:id] if entry[:id]
              o[:parent_path] = entry[:path]
              o
            end
          end
          out
        when :not_modified
          :not_modified
        else
          raise(RuntimeError, "Invalid result from server: #{res.inspect}")
        end
      end

      def process_basic_remote_props(res)
        out = {}
        out[:path]     = remote_to_relative_path(res[:path])
        out[:modified] = parse_time(res[:modified])
        out[:is_dir]   = res[:is_dir]
        out[:hash]     = res[:hash] if res[:hash]
        out[:revision] = res[:rev] if res[:rev]
        out
      end

      def generate_tmpfilename(path)
        out = File.join(local_path, ".#{path.gsub(/\W/, '-')}.part")
        if File.exists?(out)
          generate_tmpfilename("path#{rand(1000)}")
        else
          out
        end
      end

      def remove_tmpfiles
        Dir["#{local_path}/.*.part"].each {|f| FileUtils.rm(f) }
      end
    end

    class Pull < Operation
      def initialize(database, api)
        super(database, api)
      end

      def practice
        dir = database.root_dir
        changes = calculate_changes(dir)
        log.debug "Changes that would be executed:\n" + changes.map {|c| c.inspect }.join("\n")
      end

      def execute
        remove_tmpfiles
        dir = database.root_dir
        changes = calculate_changes(dir)
        log.debug "Executing changes:\n" + changes.map {|c| c.inspect }.join("\n")
        parent_ids_of_failed_entries = []
        changelist = { :created => [], :deleted => [], :updated => [], :failed => [] }

        # spin up a parallel task queue
        ptasks = ParallelTasks.new(MAX_PARALLEL_DBOX_OPS - 1) { clone_api_into_current_thread() }
        ptasks.start

        changes.each do |op, c|
          case op
          when :create
            c[:parent_id] ||= lookup_id_by_path(c[:parent_path])
            if c[:is_dir]
              # directory creation cannot go in a thread, since later
              # operations might depend on the directory being there
              create_dir(c)
              database.add_entry(c[:path], true, c[:parent_id], c[:modified], c[:revision], c[:hash])
              changelist[:created] << c[:path]
            else
              ptasks.add do
                begin
                  create_file(c)
                  database.add_entry(c[:path], false, c[:parent_id], c[:modified], c[:revision], c[:hash])
                  changelist[:created] << c[:path]
                rescue Dbox::ServerError => e
                  log.error "Error while downloading #{c[:path]}: #{e.inspect}"
                  parent_ids_of_failed_entries << c[:parent_id]
                  changelist[:failed] << { :operation => :create, :path => c[:path], :error => e }
                end
              end
            end
          when :update
            if c[:is_dir]
              update_dir(c)
              database.update_entry_by_path(c[:path], :modified => c[:modified], :revision => c[:revision], :hash => c[:hash])
              changelist[:updated] << c[:path]
            else
              ptasks.add do
                begin
                  update_file(c)
                  database.update_entry_by_path(c[:path], :modified => c[:modified], :revision => c[:revision], :hash => c[:hash])
                  changelist[:updated] << c[:path]
                rescue Dbox::ServerError => e
                  log.error "Error while downloading #{c[:path]}: #{e.inspect}"
                  parent_ids_of_failed_entries << c[:parent_id]
                  changelist[:failed] << { :operation => :create, :path => c[:path], :error => e }
                end
              end
            end
          when :delete
            c[:is_dir] ? delete_dir(c) : delete_file(c)
            database.delete_entry_by_path(c[:path])
            changelist[:deleted] << c[:path]
          else
            raise(RuntimeError, "Unknown operation type: #{op}")
          end
        end

        # wait for operations to finish
        ptasks.finish

        # clear hashes on any dirs with children that failed so that
        # they are processed again on next pull
        parent_ids_of_failed_entries.uniq.each do |id|
          database.update_entry_by_id(id, :hash => nil)
        end

        # sort & return output
        changelist.keys.each {|k| changelist[k].sort! }
        changelist
      end

      def calculate_changes(dir, operation = :update)
        raise(ArgumentError, "Not a directory: #{dir.inspect}") unless dir[:is_dir]

        out = []
        recur_dirs = []

        # grab the metadata for the current dir (either off the filesystem or from Dropbox)
        res = gather_remote_info(dir)
        if res == :not_modified
          # directory itself was not modified, but we still need to
          # recur on subdirectories
          recur_dirs += database.subdirs(dir[:id]).map {|d| [:update, d] }
        else
          raise(ArgumentError, "Not a directory: #{res.inspect}") unless res[:is_dir]

          # dir may have changed -- calculate changes on contents
          contents = res.delete(:contents)
          if operation == :create || modified?(dir, res)
            res[:parent_id] = dir[:parent_id] if dir[:parent_id]
            res[:parent_path] = dir[:parent_path] if dir[:parent_path]
            out << [operation, res]
          end
          found_paths = []
          existing_entries = current_dir_entries_as_hash(dir)

          # process each entry that came back from dropbox/filesystem
          contents.each do |c|
            found_paths << c[:path]
            if entry = existing_entries[c[:path]]
              c[:id] = entry[:id]
              c[:modified] = parse_time(c[:modified])
              if c[:is_dir]
                # queue dir for later
                c[:hash] = entry[:hash]
                recur_dirs << [:update, c]
              else
                # update iff modified
                out << [:update, c] if modified?(entry, c)
              end
            else
              # create
              c[:modified] = parse_time(c[:modified])
              if c[:is_dir]
                # queue dir for later
                recur_dirs << [:create, c]
              else
                out << [:create, c]
              end
            end
          end

          # add any deletions
          out += (existing_entries.keys.sort - found_paths.sort).map do |p|
            [:delete, existing_entries[p]]
          end
        end

        # recursively process new & existing subdirectories in parallel
        threads = recur_dirs.map do |operation, dir|
          Thread.new do
            clone_api_into_current_thread()
            Thread.current[:out] = calculate_changes(dir, operation)
          end
        end
        threads.each {|t| t.join; out += t[:out] }

        out
      end

      def modified?(entry, res)
        out = (entry[:revision] != res[:revision]) ||
              (time_to_s(entry[:modified]) != time_to_s(res[:modified]))
        out ||= (entry[:hash] != res[:hash]) if res.has_key?(:hash)
        log.debug "#{entry[:path]} modified? r#{entry[:revision]} vs. r#{res[:revision]}, h#{entry[:hash]} vs. h#{res[:hash]}, t#{time_to_s(entry[:modified])} vs. t#{time_to_s(res[:modified])} => #{out}"
        out
      end

      def create_dir(dir)
        local_path = relative_to_local_path(dir[:path])
        log.info "Creating #{local_path}"
        saving_parent_timestamp(dir) do
          FileUtils.mkdir_p(local_path)
          update_file_timestamp(dir)
        end
      end

      def update_dir(dir)
        update_file_timestamp(dir)
      end

      def delete_dir(dir)
        local_path = relative_to_local_path(dir[:path])
        log.info "Deleting #{local_path}"
        saving_parent_timestamp(dir) do
          FileUtils.rm_r(local_path)
        end
      end

      def create_file(file)
        saving_parent_timestamp(file) do
          download_file(file)
        end
      end

      def update_file(file)
        download_file(file)
      end

      def delete_file(file)
        local_path = relative_to_local_path(file[:path])
        log.info "Deleting file: #{local_path}"
        saving_parent_timestamp(file) do
          FileUtils.rm_rf(local_path)
        end
      end

      def download_file(file)
        local_path = relative_to_local_path(file[:path])
        remote_path = relative_to_remote_path(file[:path])

        # stream download to temp file, then atomic move to real path
        tmp = generate_tmpfilename(file[:path])
        File.open(tmp, "w") do |f|
          f <<  api.get_file(remote_path)
        end
        FileUtils.mv(tmp, local_path)

        update_file_timestamp(file)
      end
    end

    class Push < Operation
      def initialize(database, api)
        super(database, api)
      end

      def practice
        dir = database.root_dir
        changes = calculate_changes(dir)
        log.debug "Changes that would be executed:\n" + changes.map {|c| c.inspect }.join("\n")
      end

      def execute
        dir = database.root_dir
        changes = calculate_changes(dir)
        log.debug "Executing changes:\n" + changes.map {|c| c.inspect }.join("\n")
        changelist = { :created => [], :deleted => [], :updated => [], :failed => [] }

        # spin up a parallel task queue
        ptasks = ParallelTasks.new(MAX_PARALLEL_DBOX_OPS - 1) { clone_api_into_current_thread() }
        ptasks.start

        changes.each do |op, c|
          case op
          when :create
            c[:parent_id] ||= lookup_id_by_path(c[:parent_path])

            if c[:is_dir]
              # directory creation cannot go in a thread, since later
              # operations might depend on the directory being there
              create_dir(c)
              database.add_entry(c[:path], true, c[:parent_id], nil, nil, nil)
              force_metadata_update_from_server(c)
              changelist[:created] << c[:path]
            else
              # spin up a thread to upload the file
              ptasks.add do
                begin
                  upload_file(c)
                  database.add_entry(c[:path], false, c[:parent_id], nil, nil, nil)
                  force_metadata_update_from_server(c)
                  changelist[:created] << c[:path]
                rescue Dbox::ServerError => e
                  log.error "Error while uploading #{c[:path]}: #{e.inspect}"
                  changelist[:failed] << { :operation => :create, :path => c[:path], :error => e }
                end
              end
            end
          when :update
            existing = database.find_by_path(c[:path])
            unless existing[:is_dir] == c[:is_dir]
              raise(RuntimeError, "Mode on #{c[:path]} changed between file and dir -- not supported yet")
            end

            # only update files -- nothing to do to update a dir
            if !c[:is_dir]

              # spin up a thread to upload the file
              ptasks.add do
                begin
                  upload_file(c)
                  force_metadata_update_from_server(c)
                  changelist[:updated] << c[:path]
                rescue Dbox::ServerError => e
                  log.error "Error while uploading #{c[:path]}: #{e.inspect}"
                  changelist[:failed] << { :operation => :update, :path => c[:path], :error => e }
                end
              end
            end
          when :delete
            # spin up a thread to delete the file/dir
            ptasks.add do
              begin
                begin
                  if c[:is_dir]
                    delete_dir(c)
                  else
                    delete_file(c)
                  end
                rescue Dbox::RemoteMissing
                  # safe to delete even if remote is already gone
                end
                database.delete_entry_by_path(c[:path])
                changelist[:deleted] << c[:path]
              rescue Dbox::ServerError => e
                log.error "Error while deleting #{c[:path]}: #{e.inspect}"
                changelist[:failed] << { :operation => :delete, :path => c[:path], :error => e }
              end
            end
          else
            raise(RuntimeError, "Unknown operation type: #{op}")
          end
        end

        # wait for operations to finish
        ptasks.finish

        # sort & return output
        changelist.keys.each {|k| changelist[k].sort! }
        changelist
      end

      def calculate_changes(dir)
        raise(ArgumentError, "Not a directory: #{dir.inspect}") unless dir[:is_dir]

        out = []
        recur_dirs = []

        existing_entries = current_dir_entries_as_hash(dir)
        child_paths = list_contents(dir).sort

        child_paths.each do |p|
          c = { :path => p, :modified => mtime(p), :is_dir => is_dir(p), :parent_path => dir[:path] }
          if entry = existing_entries[p]
            c[:id] = entry[:id]
            recur_dirs << c if c[:is_dir] # queue dir for later
            out << [:update, c] if modified?(entry, c) # update iff modified
          else
            # create
            out << [:create, c]
            recur_dirs << c if c[:is_dir]
          end
        end

        # add any deletions
        out += (existing_entries.keys.sort - child_paths).map do |p|
          [:delete, existing_entries[p]]
        end

        # recursively process new & existing subdirectories
        recur_dirs.each do |dir|
          out += calculate_changes(dir)
        end

        out
      end

      def mtime(path)
        File.mtime(relative_to_local_path(path))
      end

      def is_dir(path)
        File.directory?(relative_to_local_path(path))
      end

      def modified?(entry, res)
        out = time_to_s(entry[:modified]) != time_to_s(res[:modified])
        log.debug "#{entry[:path]} modified? t#{time_to_s(entry[:modified])} vs. t#{time_to_s(res[:modified])} => #{out}"
        out
      end

      def list_contents(dir)
        local_path = relative_to_local_path(dir[:path])
        paths = Dir.entries(local_path).reject {|s| s == "." || s == ".." || s.start_with?(".") }
        paths.map {|p| local_to_relative_path(File.join(local_path, p)) }
      end

      def create_dir(dir)
        remote_path = relative_to_remote_path(dir[:path])
        log.info "Creating #{remote_path}"
        api.create_dir(remote_path)
      end

      def delete_dir(dir)
        remote_path = relative_to_remote_path(dir[:path])
        api.delete_dir(remote_path)
      end

      def delete_file(file)
        remote_path = relative_to_remote_path(file[:path])
        api.delete_file(remote_path)
      end

      def upload_file(file)
        local_path = relative_to_local_path(file[:path])
        remote_path = relative_to_remote_path(file[:path])
        File.open(local_path) do |f|
          api.put_file(remote_path, f, false, file[:rev])
        end
      end

      def force_metadata_update_from_server(entry)
        res = gather_remote_info(entry)
        unless res == :not_modified
          database.update_entry_by_path(entry[:path], :modified => res[:modified], :revision => res[:revision], :hash => res[:hash])
        end
        update_file_timestamp(database.find_by_path(entry[:path]))
      end
    end
  end
end
