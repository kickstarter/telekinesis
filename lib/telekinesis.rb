require "java"
require "telekinesis/version"
require "telekinesis/telekinesis-#{Telekinesis::VERSION}.jar"

require "telekinesis/config"
require "telekinesis/consumer/block_consumer"

java_import com.amazonaws.services.kinesis.AmazonKinesisClient


module Telekinesis
  class << self
    def process_records(config_hash = {}, &block)
      consumer(config_hash) { BlockRecordProcessor.new(&block) }
    end

    def consumer(config_hash = {}, &block)
      # Closure conversion generates an IRecordProcessorFactory from &block
      com.kickstarter.jruby.Telekinesis::new_worker(Config::consumer_config(config_hash), &block)
    end
  end
end
