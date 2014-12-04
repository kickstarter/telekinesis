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
      @last_put_at = current_time_millis

      # NOTE: instance variables are effectively volatile. Don't need them to be
      #       Atomic to ensure visibility.
      @shutdown = false
    end

    def run
      loop do
        # Wait until poll_timeout ms after the last put. This isn't a fixed wait
        # time, data might have shown up in between then and now.
        next_wait = [0, (@last_put_at + @poll_timeout) - current_time_millis].max
        next_record = @queue.poll(next_wait, TimeUnit::MILLISECONDS)

        # Shutdown when the signal is given. Always flush on shutdown so that
        # there's no data stranded in this serializer.
        if next_record == SHUTDOWN
          next_record, @shutdown = nil, true
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
            Telekinesis.stats.increment("serializer.write_failures.#{@stream}")
            Telekinesis.logger.error("Error serializing record")
            Telekinesis.logger.error(e)
            next
          end
        else
          Telekinesis.logger.debug("Hit max wait time. Flushing queued data.")
          Telekinesis.stats.increment("worker.poll_timed_out.#{@stream}")
          result = @serializer.flush
        end

        put_data(result) if result
        @last_put_at = current_time_millis
        break if @shutdown
      end
    rescue => e
      Telekinesis.logger.error("Producer background thread died!")
      Telekinesis.logger.error(e)
      Telekinesis.stats.increment("worker.uncaught_exceptions.#{@stream}")
      raise e
    end

    protected

    def current_time_millis
      (Time.now.to_f * 1000).to_i
    end

    def put_data(data, retries = 5, retry_interval = 1)
      request = build_request(data)

      tries = retries
      begin
        Telekinesis.stats.time("#{@stream}.kinesis.put_records.time") do
          @client.put_record(request)
        end
      rescue => e
        # NOTE: AWS errors are often transient. Just back off and sleep, debug
        #       log it.
        Telekinesis.logger.debug("Error sending data to Kinesis (#{tries} retries remaining): #{e}")
        if (tries -= 1) > 0
          sleep retry_interval
          Telekinesis.stats.increment("kinesis.put_records.retries.#{@stream}")
          retry
        end
        Telekinesis.logger.error("Request to Kinesis failed after #{retries} retries " +
                                 "(stream=#{request.stream_name} partition_key=#{request.partition_key}).")
        Telekinesis.stats.increment("kinesis.put_records.failures.#{@stream}")
      end
    end

    def build_request(payload)
      # NOTE: Timing is the only way to get a distribution
      Telekinesis.stats.timing("kinesis.put_records.payload_size.#{@stream}", payload.size)

      request = PutRecordRequest.new
      request.stream_name = @stream
      request.data = ByteBuffer.wrap(payload)
      request.partition_key = hash_code(payload).to_string
      request
    end

    def hash_code(data)
      Producer::MURMUR_3_128.new_hasher.put_bytes(data).hash()
    end
  end
end
