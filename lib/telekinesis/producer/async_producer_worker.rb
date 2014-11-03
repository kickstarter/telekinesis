module Telekinesis
  module Producer
    java_import java.nio.ByteBuffer
    java_import java.util.concurrent.TimeUnit
    java_import com.amazonaws.services.kinesis.model.PutRecordsRequest
    java_import com.amazonaws.services.kinesis.model.PutRecordsRequestEntry

    class AsyncProducerWorker
      SHUTDOWN = :shutdown

      def initialize(producer, queue, send_size, send_every, retries, retry_interval)
        @producer = producer
        @queue = queue
        @send_size = send_size
        @send_every = send_every
        @retries = retries
        @retry_interval = retry_interval

        @stream = producer.stream                   # for convenience
        @client = producer.client                   # for convenience
        @failure_handler = producer.failure_handler # for convenience

        @buffer = []
        @last_poll_at = current_time_millis
        @shutdown = false
      end

      def run
        loop do
          next_wait = [0, (@last_poll_at + @send_every) - current_time_millis].max
          next_item = @queue.poll(next_wait, TimeUnit::MILLISECONDS)

          if next_item == SHUTDOWN
            next_item, @shutdown = nil, true
          end

          unless next_item.nil?
            buffer(next_item)
          end

          if buffer_full || (next_item.nil? && buffer_has_records)
            put_records(get_and_reset_buffer, @retries, @retry_interval)
          end

          @last_poll_at = current_time_millis
          break if @shutdown
        end
      rescue => e
        # TODO: is there a way to encourage people to set up an uncaught exception
        # hanlder and/or disable this?
        bt = e.backtrace ? e.backtrace.map{|l| "!  #{l}"}.join("\n") : ""
        warn "Producer background thread died!"
        warn "#{e.class}: #{e.message}\n#{bt}"
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
        @buffer.size == @send_size
      end

      def buffer_has_records
        !@buffer.empty?
      end

      def get_and_reset_buffer
        ret, @buffer = @buffer, []
        ret
      end

      def put_records(items, retries, retry_interval)
        begin
          failed = []
          while retries > 0
            retryable, unretryable = @client.put_records(@stream, items).partition do |_, _, code, _|
              code == 'InternalFailure' || code == 'ProvisionedThroughputExceededException'
            end
            failed.concat(unretryable)

            if retryable.empty?
              break
            else
              items = retryable.map{|k, v, _, _| [k, v]}
              retries -= 1
            end
          end
          failed.concat(retryable) unless retryable.empty?
          @failure_handler.on_record_failure(failed) unless failed.empty?
        rescue Telekinesis::Aws::KinesisError => e
          if e.cause && e.cause.is_retryable && (retries -= 1) > 0
            sleep retry_interval
            @failure_handler.on_kinesis_retry(e, items)
            retry
          else
            @failure_handler.on_kinesis_failure(e, items)
          end
        end
      end
    end
  end
end
