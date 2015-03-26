require "logger"
require "telekinesis/logging/ruby_logger_handler"

module Telekinesis
  module Logging
    java_import java.util.logging.Logger
    java_import java.util.logging.LogManager

    def self.capture_java_logging(logger)
      LogManager.log_manager.reset
      Logger.get_logger("").add_handler(RubyLoggerHandler.new(logger))
    end

    def self.disable_java_logging
      LogManager.log_manager.reset
    end
  end
end
