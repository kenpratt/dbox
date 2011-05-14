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
      Logger.new(STDOUT)
    end
  end
end
