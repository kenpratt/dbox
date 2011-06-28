#!/usr/bin/env ruby

require "rubygems"
require "dbox"

ENV["DROPBOX_APP_KEY"] = "cmlrrjd3j0gbend"
ENV["DROPBOX_APP_SECRET"] = "uvuulp75xf9jffl"
ENV["DROPBOX_AUTH_KEY"] = "v4d7l1rez1czksn"
ENV["DROPBOX_AUTH_SECRET"] = "pqej9rmnj0i1gcxr4"

LOGFILE = "/home/myuser/dbox.log"
LOCAL_PATH = "/home/myuser/dropbox"
REMOTE_PATH = "/stuff/myfolder"
INTERVAL = 60 # time between syncs, in seconds

LOGGER = Logger.new(LOGFILE, 1, 1024000)
LOGGER.level = Logger::INFO

def main
  while 1
    begin
      sync
    rescue Interrupt => e
      exit 0
    rescue Exception => e
      LOGGER.error e
    end
    sleep INTERVAL
  end
end

def sync
  unless Dbox.exists?(LOCAL_PATH)
    LOGGER.info "Cloning"
    Dbox.clone(REMOTE_PATH, LOCAL_PATH)
    LOGGER.info "Done"
  else
    LOGGER.info "Syncing"
    Dbox.push(LOCAL_PATH)
    Dbox.pull(LOCAL_PATH)
    LOGGER.info "Done"
  end
end

main
