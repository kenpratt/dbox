module Dbox
  module Utils
    def times_equal?(t1, t2)
      time_to_s(t1) == time_to_s(t2)
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

    # assumes local_path is defined
    def local_to_relative_path(path)
      if path.include?(local_path)
        path.sub(local_path, "").sub(/^\//, "")
      else
        raise BadPath, "Not a local path: #{path}"
      end
    end

    # assumes remote_path is defined
    def remote_to_relative_path(path)
      if path.include?(remote_path)
        path.sub(remote_path, "").sub(/^\//, "")
      else
        raise BadPath, "Not a remote path: #{path}"
      end
    end

    # assumes local_path is defined
    def relative_to_local_path(path)
      if path && path.length > 0
        File.join(local_path, path)
      else
        local_path
      end
    end

    # assumes remote_path is defined
    def relative_to_remote_path(path)
      if path && path.length > 0
        File.join(remote_path, path)
      else
        remote_path
      end
    end

    def calculate_hash(filepath)
      begin
        Digest::MD5.file(filepath).to_s
      rescue Errno::EISDIR
        nil
      rescue Errno::ENOENT
        nil
      end
    end

    def find_nonconflicting_path(filepath)
      proposed = filepath
      while File.exists?(proposed)
        dir, p = File.split(proposed)
        p = p.sub(/^(.*?)( \((\d+)\))?(\..*?)?$/) { "#{$1} (#{$3 ? $3.to_i + 1 : 1})#{$4}" }
        proposed = File.join(dir, p)
      end
      proposed
    end
  end
end
