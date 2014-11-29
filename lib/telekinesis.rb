require "java"
# Make sure that commons logging uses JUL. Set the system property before
# the JAR is loaded to make sure that it's picked up as soon as possible.
java.lang.System.set_property("org.apache.commons.logging.Log",
                              "org.apache.commons.logging.impl.Jdk14Logger")

require "telekinesis/version"
require "telekinesis/telekinesis-#{Telekinesis::VERSION}.jar"

require "telekinesis/logging"
require "telekinesis/config"
require "telekinesis/producer"
require "telekinesis/consumer/block_consumer"

java_import com.amazonaws.services.kinesis.AmazonKinesisClient

Telekinesis::Logging.capture_java_logging

module Telekinesis
  FIFTY_KB = 50 * 1024
  DEFAULT_DELIMITER = "\n"

  class << self
    def producer(config_hash = {}, &block)
      stream, creds_provider = Config.producer_config(config_hash)
      client = AmazonKinesisClient.new(creds_provider)
      serializer = block_given? ? block : default_serializer
      Producer.new(stream, client, config_hash, &serializer)
    end

    def process_records(config_hash = {}, &block)
      consumer(config_hash) { BlockRecordProcessor.new(&block) }
    end

    def consumer(config_hash = {}, &block)
      # Closure conversion generates an IRecordProcessorFactory from &block
      com.kickstarter.jruby.Telekinesis::new_worker(Config.consumer_config(config_hash), &block)
    end

    protected

    def default_serializer
      Proc.new { GZIPDelimitedSerializer.new(FIFTY_KB, DEFAULT_DELIMITER) }
    end
  end
end
