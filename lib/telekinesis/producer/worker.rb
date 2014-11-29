java_import java.nio.ByteBuffer
java_import java.util.concurrent.TimeUnit
java_import com.amazonaws.services.kinesis.model.PutRecordRequest

module Telekinesis
  class ShutdownCommand; end

  class ProducerWorker
    include java.lang.Runnable

    SHUTDOWN = ShutdownCommand.new

    def initialize(stream, queue, client, poll_timeout, serializer)
      @stream = stream
      @queue = queue
      @client = client
      @poll_timeout = poll_timeout
      @serializer = serializer

      # NOTE: instance variables are effectively volatile. Don't need them to be
      #       Atomic to ensure visibility.
      @shutdown = false
      @flush_next = false
    end

    def flush
      @flush_next = true
    end

    def run
      loop do
        next_record = @queue.poll(@poll_timeout, TimeUnit::MILLISECONDS)

        # NOTE: Shutdown when the signal is given. Always flush on shutdown so
        #       that there's no data stranded in this serializer.
        if next_record == SHUTDOWN
          next_record, @shutdown, @flush_next = nil, true, true
        end

        # NOTE: The serializer is responsible for handling any exceptions
        #       raised while dealing with input. Anything that escapes is
        #       assumed to be unhandleable, so the record should just be
        #       dropped.
        result = nil
        if not next_record.nil?
          begin
            result = @serializer.write(next_record)
          rescue => e
            Telekinesis.logger.error("Error serializing record: #{e}")
            next
          end
        end

        # NOTE: The value of flush_next can change while the call to result.nil?
        #       happens. That's fine. It doesn't really matter.
        if result.nil? && @flush_next
          result = @serializer.flush
        end

        # NOTE: flip the flag back here no matter what:
        #         result.nil? => flushed already
        #         !result.nil? => the last record flushed, so there's new data being sent.
        @flush_next = false
        if result
          put_data(result)
        end

        break if @shutdown
      end
    rescue => e
      Telekinesis.logger.error("Producer background thread died!")
      Telekinesis.logger.error(e)
      raise e
    end

    protected

    def put_data(data, retries = 5, retry_interval = 1)
      request = build_request(@stream, data)
      tries = retries
      begin
        @client.put_record(request)
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

    def build_request(stream, payload)
      request = PutRecordRequest.new
      request.stream_name = stream
      request.data = ByteBuffer.wrap(payload)
      request.partition_key = hash_code(payload).to_string
      request
    end

    def hash_code(data)
      Producer::MURMUR_3_128.new_hasher.put_bytes(data).hash()
    end
  end

end
