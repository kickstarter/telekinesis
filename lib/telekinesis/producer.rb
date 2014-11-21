require "telekinesis/producer/sync_handler"
require "telekinesis/producer/async_handler"
require "telekinesis/producer/serializer"

java_import java.nio.ByteBuffer
java_import com.google.common.hash.Hashing
java_import com.amazonaws.services.kinesis.model.PutRecordRequest

module Telekinesis
  ##
  # A high-level producer for records that should be batched together before
  # being sent to Kinesis. Assumes that batches of records should be
  # distributed evenly across the shards in a stream.
  #
  # This class is thread-safe.
  class Producer
    MURMUR_3_123 = Hashing.murmur3_128()

    def self.build_request(stream, payload)
      request = PutRecordRequest.new
      request.stream_name = stream
      request.data = ByteBuffer.wrap(payload)
      request.partition_key = hash_code(payload).to_string
      request
    end

    def self.put_data(client, stream, data, retries = 5, retry_interval = 3)
      request = build_request(stream, data)
      tries = retries
      begin
        client.put_record(request)
      rescue => e
        # NOTE: AWS errors are often transient. Just back off and sleep, debug
        #       log it.
        Telekinesis.logger.debug("Error sending data to Kinesis (#{tries} retries remaining): #{e}")
        if (tries -= 1) > 0
          sleep retry_interval
          retry
        end
        Telekinesis.logger.error("Request to Kinesis failed after #{retries} retries " +
                                 "(stream=#{request.stream_name} partition_key=#{request.partition_key}).")
        raise
      end
    end

    attr_reader :handler

    def initialize(handler)
      @handler = handler
    end

    def stream
      handler.stream
    end

    def put(record)
      handler.handle(record)
    end

    def flush
      handler.flush
    end

    def shutdown(block = false, duration = 2, unit = TimeUnit::SECONDS)
      handler.shutdown(block, duration, unit)
    end

    def await(duration = 10, unit = TimeUnit::SECONDS)
      handler.await(duration, unit)
    end

    protected

    def self.hash_code(data)
      MURMUR_3_123.new_hasher.put_bytes(data).hash()
    end
  end
end
