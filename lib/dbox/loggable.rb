module Dbox
  module Loggable
    def self.included receiver
      receiver.extend ClassMethods
    end

    module ClassMethods
      def log
        Dbox.log
      end
    end

    def log
      Dbox.log
    end
  end

  def self.log
    @logger ||= setup_logger
  end

  def self.setup_logger
    if defined?(LOGGER)
      LOGGER
    elsif defined?(Rails.logger)
      Rails.logger
    else
      l = Logger.new(STDOUT)
      l.level = (ENV["DEBUG"] && ENV["DEBUG"] != "false") ? Logger::DEBUG : Logger::INFO
      l.formatter = proc {|severity, datetime, progname, msg| "[#{severity}] #{msg}\n" }
      l
    end
  end
end
