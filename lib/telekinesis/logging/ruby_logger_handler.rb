module Telekinesis
  module Logging
    java_import java.util.logging.Level
    java_import java.util.logging.Handler

    # A java logging Handler that delegates to a Ruby logger. The name of the
    # j.u.l. logger is used as the progname argument to Logger.add.
    #
    # The translation between j.u.l. serverity levels and Ruby Logger levels
    # isn't exact.
    class RubyLoggerHandler < Handler
      # NOTE: Since this class overrides a Java class, we have to use the Java
      # constructor and set the logger after instantiation. (Overriding in
      # JRuby is weird). Use this method to create a new logger that delegates
      # to the passed logger.
      def self.create(logger)
        new.tap do |s|
          s.set_logger(logger)
        end
      end

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

      def set_logger(l)
        @logger = l
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
