java_import java.util.concurrent.TimeUnit
java_import java.util.concurrent.Executors
java_import java.util.concurrent.ArrayBlockingQueue
java_import java.util.concurrent.atomic.AtomicBoolean
java_import com.google.common.util.concurrent.ThreadFactoryBuilder

module Telekinesis
  class AsyncHandler

    attr_reader :stream

    def initialize(stream, client, options = {}, &block)
      raise ArgumentError if !block_given?

      @stream = stream
      @client = client
      @shutdown = AtomicBoolean.new(false)
      @queue = ArrayBlockingQueue.new(options[:queue_size] || 1000)

      # Create workers outside of pool.submit so that the handler can keep
      # a reference to each worker for calls to flush and shutdown.
      @poll_timeout = options[:poll_timeout] || 1000
      worker_count = options[:worker_count] || 3
      @workers = worker_count.times.map do
          AsyncHandlerWorker.new(@stream, @queue, @client, @poll_timeout, block.call)
      end

      thread_factory = ThreadFactoryBuilder.new.set_name_format("#{stream}-handler-worker-%d").build
      @worker_pool = Executors.new_fixed_thread_pool(worker_count, thread_factory)
      @workers.each{ |w| @worker_pool.java_send(:submit, [java.lang.Runnable.java_class], w) }
    end

    def handle(record)
      if @shutdown.get
        false
      else
        @queue.put(record)
        true
      end
    end

    def flush
      @workers.map(&:flush)
    end

    def shutdown
      # NOTE: Not necessary to interrupt workers. They check in again every
      #       @poll_timeout millis
      @shutdown.set(true)
      @workers.map(&:shutdown)
      @worker_pool.shutdown
    end

    def await(duration = 10, unit = TimeUnit::SECONDS)
      @worker_pool.await_termination(duration, unit)
    end

    def drain(duration, interval, unit)
      # Stop accepting new work, don't shut down workers.
      @shutdown.set(true)
      # Sleep up to duration, checking in every interval
      (duration / interval).to_i.times do
        break if @queue.size == 0
        unit.sleep(interval)
      end

      flush
      # TODO: bad use of sleep. Have a shutdown latch on each worker?
      java.lang.Thread.sleep(2 * @poll_timeout)
      shutdown
      @queue
    end
  end

  class AsyncHandlerWorker
    include java.lang.Runnable

    def initialize(stream, queue, client, poll_timeout, serializer)
      @stream = stream
      @queue = queue
      @client = client
      @poll_timeout = poll_timeout
      @serializer = serializer

      @shutdown = AtomicBoolean.new(false)
      @flush_next = AtomicBoolean.new(false)
    end

    def flush
      @flush_next.set(true)
    end

    def shutdown
      @shutdown.set(true)
    end

    def run
      begin
        loop do
          next_record = @queue.poll(@poll_timeout, TimeUnit::MILLISECONDS)

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
          if result.nil? && @flush_next.get
            result = @serializer.flush
          end

          # NOTE: flip the flag back here no matter what:
          #         result.nil? => flushed already
          #         !result.nil? => the last record flushed, so there's new data being sent.
          @flush_next.set(false)
          if result
            put_data(result)
          end

          break if @shutdown.get
        end
      rescue => e
        Telekinesis.logger.error("Async producer thread died: #{e}")
      end
    end

    def put_data(data)
      Producer.put_data(@client, @stream, data)
    end
  end
end
