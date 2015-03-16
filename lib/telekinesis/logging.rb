require "logger"
require "telekinesis/logging/aws_logger_shim"
require "telekinesis/logging/noop_logger_shim"

java_import java.util.logging.Logger
java_import java.util.logging.LogManager

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
      LogManager.log_manager.reset
      root_logger.add_handler(RubyLoggerHandler.new(Telekinesis.aws_logger))
    end

    def self.disable_java_logging
      LogManager.log_manager.reset
    end

    protected

    def self.root_logger
      Logger.get_logger("")
    end
  end
end
