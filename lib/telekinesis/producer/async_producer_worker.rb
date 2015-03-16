java_import com.google.common.hash.Hashing
java_import java.nio.ByteBuffer
java_import java.util.concurrent.TimeUnit
java_import com.amazonaws.services.kinesis.model.PutRecordsRequest
java_import com.amazonaws.services.kinesis.model.PutRecordsRequestEntry

module Telekinesis
  class AsyncProducerWorker
    # NOTE: This isn't configurable right now because it's a Kinesis API limit.
    # TODO: Set an option to lower this.
    MAX_BUFFER_SIZE = 500

    def initialize(producer, queue, send_every)
      @producer = producer
      @queue    = queue
      @stream   = producer.stream  # for convenience
      @client   = producer.client  # for convenience

      @send_every = send_every
      @last_put_at = current_time_millis

      # NOTE: instance variables are volatile by default
      @buffer = []
      @shutdown = false
    end

    def run
      loop do
        next_wait = [0, (@last_put_at + @send_every) - current_time_millis].max
        next_item = @queue.poll(next_wait, TimeUnit::MILLISECONDS)

        if next_item == ProducerWorker::SHUTDOWN
          next_item, @shutdown = nil, true
        end

        unless next_item.nil?
          buffer(next_item)
        end

        if buffer_full || (next_item.nil? && buffer_has_records)
          put_records(build_request(get_and_reset_buffer))
        end

        break if @shutdown
      end
    rescue => e
      Telekinesis.logger.error("Producer background thread died!")
      Telekinesis.logger.error(e)
      raise e
    end

    protected

    def current_time_millis
      (Time.now.to_f * 1000).to_i
    end

    def buffer(item)
      @buffer << item
    end

    def buffer_full
      @buffer.size == MAX_BUFFER_SIZE
    end

    def buffer_has_records
      !@buffer.empty?
    end

    def get_and_reset_buffer
      ret, @buffer = @buffer, []
      ret
    end

    def put_records(request, retries = 5, retry_interval = 1.0)
      begin
        response = Telekinesis.stats.time("kinesis.put_records.time.#{@stream}") do
          @client.put_records(request)
        end
        if response.failed_record_count > 0
          @producer.on_failure(
            response.failed_record_count,
            response.get_records.reject{|r| r.error_code.nil?}
          )
        end
      rescue => e
        Telekinesis.logger.debug("Error sending data to Kinesis (#{retries} retries remaining): #{e}")
        if (retries -= 1) > 0
          sleep retry_interval
          retry
        end
        Telekinesis.logger.error("PutRecords request to Kinesis failed after #{retries} retries")
        Telekinesis.logger.error(e)
      end
    end

    def build_request(items)
      PutRecordsRequest.new.tap do |request|
        request.stream_name = @stream
        request.records = items.map do |key, data|
          PutRecordsRequestEntry.new.tap do |entry|
            entry.partition_key = key
            entry.data = ByteBuffer.wrap(data.to_java_bytes)
          end
        end
      end
    end
  end
end
