module Dbox
  class DatabaseError < RuntimeError; end

  class Database
    include Loggable

    DB_FILENAME = ".dbox.sqlite3"

    def self.create(remote_path, local_path)
      db = new(local_path)
      if db.bootstrapped?
        raise DatabaseError, "Database already initialized -- please use 'dbox pull' or 'dbox push'."
      end
      db.bootstrap(remote_path, local_path)
      db
    end

    def self.load(local_path)
      db = new(local_path)
      unless db.bootstrapped?
        raise DatabaseError, "Database not initialized -- please run 'dbox create' or 'dbox clone'."
      end
      db
    end

    # IMPORTANT: Database.new is private. Please use Database.create
    # or Database.load as the entry point.
    private_class_method :new
    def initialize(local_path)
      FileUtils.mkdir_p(local_path)
      @db = SQLite3::Database.new(File.join(local_path, DB_FILENAME))
      @db.trace {|sql| log.debug sql.strip }
      ensure_schema_exists
    end

    def ensure_schema_exists
      # TODO run performance tests with and without the indexes on DBs with 10,000s of records
      @db.execute_batch(%{
        CREATE TABLE IF NOT EXISTS metadata (
          id           integer PRIMARY KEY AUTOINCREMENT NOT NULL,
          local_path   varchar(255) NOT NULL,
          remote_path  varchar(255) NOT NULL,
          version      integer NOT NULL
        );
        CREATE TABLE IF NOT EXISTS entries (
          id           integer PRIMARY KEY AUTOINCREMENT NOT NULL,
          path         varchar(255) UNIQUE NOT NULL,
          is_dir       boolean NOT NULL,
          parent_id    integer,
          hash         varchar(255),
          modified     datetime,
          revision     integer
        );
        CREATE INDEX IF NOT EXISTS entry_paths ON entries(path);
        CREATE INDEX IF NOT EXISTS entry_parent_ids ON entries(parent_id);
      })
    end

    METADATA_COLS = [ :local_path, :remote_path, :version ] # don't need to return id
    ENTRY_COLS    = [ :id, :path, :is_dir, :parent_id, :hash, :modified, :revision ]

    def bootstrap(remote_path, local_path)
      @db.execute(%{
        INSERT INTO metadata (local_path, remote_path, version) VALUES (?, ?, ?);
      }, local_path, remote_path, 1)
      @db.execute(%{
        INSERT INTO entries (path, is_dir) VALUES (?, ?)
      }, "", 1)
    end

    def bootstrapped?
      n = @db.get_first_value(%{
        SELECT count(id) FROM metadata LIMIT 1;
      })
      n && n > 0
    end

    def metadata
      cols = METADATA_COLS
      res = @db.get_first_row(%{
        SELECT #{cols.join(',')} FROM metadata LIMIT 1;
      })
      make_hash(cols, res) if res
    end

    def root_dir
      find_entry("WHERE parent_id is NULL")
    end

    def find_by_path(path)
      raise(ArgumentError, "path cannot be null") unless path
      find_entry("WHERE path=?", path)
    end

    def contents(dir_id)
      raise(ArgumentError, "dir_id cannot be null") unless dir_id
      find_entries("WHERE parent_id=?", dir_id)
    end

    def subdirs(dir_id)
      raise(ArgumentError, "dir_id cannot be null") unless dir_id
      find_entries("WHERE parent_id=? AND is_dir=1", dir_id)
    end

    def add_entry(path, is_dir, parent_id, modified, revision)
      insert_entry(:path => path, :is_dir => is_dir, :parent_id => parent_id, :modified => modified, :revision => revision)
    end

    def update_entry_by_path(path, fields)
      raise(ArgumentError, "path cannot be null") unless path
      update_entry(["WHERE path=?", path], fields)
    end

    def delete_entry_by_path(path)
      raise(ArgumentError, "path cannot be null") unless path
      delete_entry("WHERE path=?", path)
    end

    private

    def find_entry(conditions = "", *args)
      res = @db.get_first_row(%{
        SELECT #{ENTRY_COLS.join(",")} FROM entries #{conditions} LIMIT 1;
      }, *args)
      entry_res_to_hash(res)
    end

    def find_entries(conditions = "", *args)
      out = []
      @db.execute(%{
        SELECT #{ENTRY_COLS.join(",")} FROM entries #{conditions} ORDER BY path ASC;
      }, *args) do |res|
        out << entry_res_to_hash(res)
      end
      out
    end

    def insert_entry(hash)
      h = hash.clone
      h[:modified]  = h[:modified].to_i if h[:modified]
      h[:is_dir] = (h[:is_dir] ? 1 : 0) unless h[:is_dir].nil?
      @db.execute(%{
        INSERT INTO entries (#{h.keys.join(",")})
        VALUES (#{(["?"] * h.size).join(",")});
      }, *h.values)
    end

    def update_entry(where_clause, hash)
      h = hash.clone
      h[:modified]  = h[:modified].to_i if h[:modified]
      conditions, *args = *where_clause
      set_str = h.keys.map {|k| "#{k}=?" }.join(",")
      @db.execute(%{
        UPDATE entries SET #{set_str} #{conditions};
      }, *(h.values + args))
    end

    def delete_entry(conditions = "", *args)
      @db.execute(%{
        DELETE FROM entries #{conditions};
      }, *args)
    end

    def entry_res_to_hash(res)
      if res
        h = make_hash(ENTRY_COLS, res)
        h[:is_dir] = (h[:is_dir] == 1)
        h[:modified]  = Time.at(h[:modified]) if h[:modified]
        h.delete(:hash) unless h[:is_dir]
        h
      else
        nil
      end
    end

    def make_hash(keys, vals)
      if keys && vals
        raise ArgumentError.new("Can't make a hash with #{keys.size} keys and #{vals.size} vals") unless keys.size == vals.size
        out = {}
        keys.each_with_index {|k, i| out[k] = vals[i] }
        out
      else
        nil
      end
    end
  end
end
