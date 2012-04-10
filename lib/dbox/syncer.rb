module Dbox
  class Syncer
    MAX_PARALLEL_DBOX_OPS = 3
    MIN_BYTES_TO_STREAM_DOWNLOAD = 1024 * 100 # 100kB

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
      include Utils

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

      def saving_timestamp(path)
        mtime = File.mtime(path)
        res = yield
        File.utime(Time.now, mtime, path)
        res
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
        res = api.metadata(relative_to_remote_path(entry[:path]), entry[:remote_hash])
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
        out[:path]        = remote_to_relative_path(res[:path])
        out[:modified]    = parse_time(res[:modified])
        out[:is_dir]      = res[:is_dir]
        out[:remote_hash] = res[:hash] if res[:hash]
        out[:revision]    = res[:rev] if res[:rev]
        out[:size]        = res[:bytes] if res[:bytes]
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

      def sort_changelist(changelist)
        changelist.keys.each do |k|
          case k
          when :conflicts
            changelist[k].sort! {|c1, c2| c1[:original] <=> c2[:original] }
          when :failed
            changelist[k].sort! {|c1, c2| c1[:path] <=> c2[:path] }
          else
            changelist[k].sort!
          end
        end
        changelist
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
              database.add_entry(c[:path], true, c[:parent_id], c[:modified], c[:revision], c[:remote_hash], nil)
              changelist[:created] << c[:path]
            else
              ptasks.add do
                begin
                  res = create_file(c)
                  local_hash = calculate_hash(relative_to_local_path(c[:path]))
                  database.add_entry(c[:path], false, c[:parent_id], c[:modified], c[:revision], c[:remote_hash], local_hash)
                  changelist[:created] << c[:path]
                  if res.kind_of?(Array) && res[0] == :conflict
                    changelist[:conflicts] ||= []
                    changelist[:conflicts] << res[1]
                  end
                rescue Exception => e
                  log.error "Error while downloading #{c[:path]}: #{e.inspect}\n#{e.backtrace.join("\n")}"
                  parent_ids_of_failed_entries << c[:parent_id]
                  changelist[:failed] << { :operation => :create, :path => c[:path], :error => e }
                end
              end
            end
          when :update
            if c[:is_dir]
              update_dir(c)
              database.update_entry_by_path(c[:path], :modified => c[:modified], :revision => c[:revision], :remote_hash => c[:remote_hash])
              changelist[:updated] << c[:path]
            else
              ptasks.add do
                begin
                  res = update_file(c)
                  local_hash = calculate_hash(relative_to_local_path(c[:path]))
                  database.update_entry_by_path(c[:path], :modified => c[:modified], :revision => c[:revision], :remote_hash => c[:remote_hash], :local_hash => local_hash)
                  changelist[:updated] << c[:path]
                  if res.kind_of?(Array) && res[0] == :conflict
                    changelist[:conflicts] ||= []
                    changelist[:conflicts] << res[1]
                  end
                rescue Exception => e
                  log.error "Error while downloading #{c[:path]}: #{e.inspect}\n#{e.backtrace.join("\n")}"
                  parent_ids_of_failed_entries << c[:parent_id]
                  changelist[:failed] << { :operation => :create, :path => c[:path], :error => e }
                end
              end
            end
          when :delete
            c[:is_dir] ? delete_dir(c) : delete_file(c)
            database.delete_entry_by_path(c[:path])
            changelist[:deleted] << c[:path]
          when :failed
            parent_ids_of_failed_entries << c[:parent_id]
            changelist[:failed] << { :operation => c[:operation], :path => c[:path], :error => c[:error] }
          else
            raise(RuntimeError, "Unknown operation type: #{op}")
          end
        end

        # wait for operations to finish
        ptasks.finish

        # clear hashes on any dirs with children that failed so that
        # they are processed again on next pull
        parent_ids_of_failed_entries.uniq.each do |id|
          database.update_entry_by_id(id, :remote_hash => nil)
        end

        # sort & return output
        sort_changelist(changelist)
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
                c[:remote_hash] = entry[:remote_hash]
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
            begin
              clone_api_into_current_thread()
              Thread.current[:out] = calculate_changes(dir, operation)
            rescue Exception => e
              log.error "Error while caclulating changes for #{operation} on #{dir[:path]}: #{e.inspect}\n#{e.backtrace.join("\n")}"
              Thread.current[:out] = [[:failed, dir.merge({ :operation => operation, :error => e })]]
            end
          end
        end
        threads.each {|t| t.join; out += t[:out] }

        out
      end

      def modified?(entry, res)
        out = (entry[:revision] != res[:revision]) ||
              !times_equal?(entry[:modified], res[:modified])
        out ||= (entry[:remote_hash] != res[:remote_hash]) if res.has_key?(:remote_hash)
        log.debug "#{entry[:path]} modified? r#{entry[:revision]} vs. r#{res[:revision]}, h#{entry[:remote_hash]} vs. h#{res[:remote_hash]}, t#{time_to_s(entry[:modified])} vs. t#{time_to_s(res[:modified])} => #{out}"
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

        # check to ensure we aren't overwriting an untracked file or a
        # file with local modifications
        clobbering = false
        if entry = database.find_by_path(file[:path])
          clobbering = calculate_hash(local_path) != entry[:local_hash]
        else
          clobbering = File.exists?(local_path)
        end

        # stream files larger than the minimum
        stream = file[:size] && file[:size] > MIN_BYTES_TO_STREAM_DOWNLOAD

        # download to temp file
        tmp = generate_tmpfilename(file[:path])
        File.open(tmp, "w") do |f|
          api.get_file(remote_path, f, stream)
        end

        # rename old file if clobbering
        if clobbering && File.exists?(local_path)
          backup_path = find_nonconflicting_path(local_path)
          FileUtils.mv(local_path, backup_path)
          backup_relpath = local_to_relative_path(backup_path)
          log.warn "#{file[:path]} had a conflict and the existing copy was renamed to #{backup_relpath} locally"
        end

        # atomic move over to the real file, and update the timestamp
        FileUtils.mv(tmp, local_path)
        update_file_timestamp(file)

        if backup_relpath
          [:conflict, { :original => file[:path], :renamed => backup_relpath }]
        else
          true
        end
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
              database.add_entry(c[:path], true, c[:parent_id], nil, nil, nil, nil)
              force_metadata_update_from_server(c)
              changelist[:created] << c[:path]
            else
              # spin up a thread to upload the file
              ptasks.add do
                begin
                  local_hash = calculate_hash(relative_to_local_path(c[:path]))
                  res = upload_file(c)
                  database.add_entry(c[:path], false, c[:parent_id], nil, nil, nil, local_hash)
                  if c[:path] == res[:path]
                    force_metadata_update_from_server(c)
                    changelist[:created] << c[:path]
                  else
                    log.warn "#{c[:path]} had a conflict and was renamed to #{res[:path]} on the server"
                    changelist[:conflicts] ||= []
                    changelist[:conflicts] << { :original => c[:path], :renamed => res[:path] }
                  end
                rescue Exception => e
                  log.error "Error while uploading #{c[:path]}: #{e.inspect}\n#{e.backtrace.join("\n")}"
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
                  local_hash = calculate_hash(relative_to_local_path(c[:path]))
                  res = upload_file(c)
                  database.update_entry_by_path(c[:path], :local_hash => local_hash)
                  if c[:path] == res[:path]
                    force_metadata_update_from_server(c)
                    changelist[:updated] << c[:path]
                  else
                    log.warn "#{c[:path]} had a conflict and was renamed to #{res[:path]} on the server"
                    changelist[:conflicts] ||= []
                    changelist[:conflicts] << { :original => c[:path], :renamed => res[:path] }
                  end
                rescue Exception => e
                  log.error "Error while uploading #{c[:path]}: #{e.inspect}\n#{e.backtrace.join("\n")}"
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
              rescue Exception => e
                log.error "Error while deleting #{c[:path]}: #{e.inspect}\n#{e.backtrace.join("\n")}"
                changelist[:failed] << { :operation => :delete, :path => c[:path], :error => e }
              end
            end
          when :failed
            changelist[:failed] << { :operation => c[:operation], :path => c[:path], :error => c[:error] }
          else
            raise(RuntimeError, "Unknown operation type: #{op}")
          end
        end

        # wait for operations to finish
        ptasks.finish

        # sort & return output
        sort_changelist(changelist)
      end

      def calculate_changes(dir)
        raise(ArgumentError, "Not a directory: #{dir.inspect}") unless dir[:is_dir]

        out = []
        recur_dirs = []

        existing_entries = current_dir_entries_as_hash(dir)
        child_paths = list_contents(dir).sort

        child_paths.each do |p|
          c = { :path => p, :modified => mtime(p), :is_dir => is_dir(p), :parent_path => dir[:path], :local_hash => calculate_hash(relative_to_local_path(p)) }
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
        out = true
        if entry[:is_dir]
          out = !times_equal?(entry[:modified], res[:modified])
          log.debug "#{entry[:path]} modified? t#{time_to_s(entry[:modified])} vs. t#{time_to_s(res[:modified])} => #{out}"
        else
          eh = entry[:local_hash]
          rh = res[:local_hash]
          out = !(eh && rh && eh == rh)
          log.debug "#{entry[:path]} modified? #{eh} vs. #{rh} => #{out}"
        end
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
        db_entry = database.find_by_path(file[:path])
        last_revision = db_entry ? db_entry[:revision] : nil
        res = api.put_file(remote_path, local_path, last_revision)
        process_basic_remote_props(res)
      end

      def force_metadata_update_from_server(entry)
        res = gather_remote_info(entry)
        unless res == :not_modified
          database.update_entry_by_path(entry[:path], :modified => res[:modified], :revision => res[:revision], :remote_hash => res[:remote_hash])
        end
        update_file_timestamp(database.find_by_path(entry[:path]))
      end
    end
  end
end
