ROOT_PATH = File.expand_path(File.join(File.dirname(__FILE__), ".."))
$:.unshift File.join(ROOT_PATH, "lib")
$:.unshift File.join(ROOT_PATH, "vendor", "dropbox-client-ruby", "lib")

require "dropbox"
require "fileutils"
require "time"
require "yaml"

require "dbox/api"
require "dbox/db"

module Dbox
  def self.authorize
    Dbox::API.authorize
  end

  def self.create(remote_path, local_path = nil)
    remote_path = clean_remote_path(remote_path)
    local_path ||= remote_path.split("/").last
    Dbox::DB.create(remote_path, local_path)
  end

  def self.clone(remote_path, local_path = nil)
    remote_path = clean_remote_path(remote_path)
    local_path ||= remote_path.split("/").last
    Dbox::DB.clone(remote_path, local_path)
  end

  def self.pull(local_path = nil)
    local_path ||= "."
    Dbox::DB.pull(local_path)
  end

  def self.push(local_path = nil)
    local_path ||= "."
    Dbox::DB.push(local_path)
  end

  private

  def self.clean_remote_path(path)
    if path
      path.sub(/\/$/,'')
      path[0] == "/" ? path : "/#{path}"
    else
      raise "Missing remote path"
    end
  end
end
