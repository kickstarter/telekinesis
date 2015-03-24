require "logger"

java_import java.util.logging.LogManager
java_import java.util.logging.Level
java_import java.util.logging.Handler

module Telekinesis
  module Logging
    def self.capture_java_logging(logger)
      LogManager.log_manager.reset
      jul_root_logger.add_handler(RubyLoggerHandler.new(logger))
    end

    def self.disable_java_logging
      LogManager.log_manager.reset
    end

    def self.jul_root_logger
      java.util.logging.Logger.get_logger("")
    end

    # A java logging Handler that delegates to a Ruby logger. The name of the
    # j.u.l. logger is used as the progname argument to Logger.add.
    #
    # The translation between j.u.l. serverity levels and Ruby Logger levels
    # isn't exact.
    class RubyLoggerHandler < Handler
      SEVERITY = {
        # NOTE: There's no Java equivalent of FATAL.
        Level::SEVERE => Logger::ERROR,
        Level::WARNING => Logger::WARN,
        Level::INFO => Logger::INFO,
        Level::CONFIG => Logger::INFO,
        Level::FINE=> Logger::DEBUG,
        Level::FINER=> Logger::DEBUG,
        Level::FINEST=> Logger::DEBUG,
      }

      def initialize(logger)
        @logger = logger
      end

      def close
        @logger.close
      end

      # Ruby's logger has no flush method.
      def flush; end

      def publish(log_record)
        message = if log_record.thrown.nil?
          log_record.message
        else
          "#{log_record.message}: #{log_record.thrown}"
        end
        @logger.add(SEVERITY[log_record.level], message, log_record.logger_name)
      end
    end
  end
end
