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

    def drain(duration = 60, interval = 1, unit = TimeUnit::SECONDS)
      handler.drain(duration, interval, unit)
    end

    protected

    def self.hash_code(data)
      MURMUR_3_123.new_hasher.put_bytes(data).hash()
    end
  end
end
