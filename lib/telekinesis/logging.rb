require "logger"
require "telekinesis/logging/aws_logger_shim"
require "telekinesis/logging/noop_logger_shim"

module Telekinesis
  @logger = Logger.new($stderr).tap do |l|
    l.level = Logger::INFO
  end
  @aws_logger = @logger

  class << self
    attr_accessor :logger
    attr_accessor :aws_logger
  end

  module Logging
    def self.capture_java_logging
      # Strip the root handler off JUL and set up the proxy. None of our deps
      # are bad enough citizens that they configure any JUL handlers on their
      # own.
      strip_handlers(root_logger).add_handler(AwsLoggerShim.new)
    end

    def self.disable_java_logging
      strip_handlers(root_logger).add_handler(NoopLoggerShim.new)
    end

    protected

    def self.root_logger
      java.util.logging.LogManager.log_manager.get_logger("")
    end

    def self.strip_handlers(logger)
      logger.get_handlers.each do |h|
        logger.remove_handler(h)
      end
      logger
    end
  end
end
