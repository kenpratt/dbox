ROOT_PATH = File.expand_path(File.join(File.dirname(__FILE__), ".."))
$:.unshift File.join(ROOT_PATH, "lib")
$:.unshift File.join(ROOT_PATH, "vendor", "dropbox-client-ruby", "lib")

require "dropbox"
require "fileutils"
require "time"
require "yaml"
require "logger"
require "cgi"
require "sqlite3"
require "active_support/core_ext/hash/indifferent_access"

require "dbox/loggable"
require "dbox/api"
require "dbox/database"
require "dbox/db"
require "dbox/syncer"

module Dbox
  def self.authorize
    Dbox::API.authorize
  end

  def self.create(remote_path, local_path)
    remote_path = clean_remote_path(remote_path)
    local_path = clean_local_path(local_path)
    Dbox::Syncer.create(remote_path, local_path)
  end

  def self.clone(remote_path, local_path)
    remote_path = clean_remote_path(remote_path)
    local_path = clean_local_path(local_path)
    Dbox::Syncer.clone(remote_path, local_path)
  end

  def self.pull(local_path)
    local_path = clean_local_path(local_path)
    Dbox::Syncer.pull(local_path)
  end

  def self.push(local_path)
    local_path = clean_local_path(local_path)
    Dbox::Syncer.push(local_path)
  end

  def self.move(new_remote_path, local_path)
    new_remote_path = clean_remote_path(new_remote_path)
    local_path = clean_local_path(local_path)
    Dbox::Syncer.move(new_remote_path, local_path)
  end

  def self.exists?(local_path)
    local_path = clean_local_path(local_path)
    Dbox::Database.exists?(local_path)
  end

  private

  def self.clean_remote_path(path)
    raise(ArgumentError, "Missing remote path") unless path
    path.sub(/\/$/,'')
    path[0].chr == "/" ? path : "/#{path}"
  end

  def self.clean_local_path(path)
    raise(ArgumentError, "Missing local path") unless path
    File.expand_path(path)
  end
end
