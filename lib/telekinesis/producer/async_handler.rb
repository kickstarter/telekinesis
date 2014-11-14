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
      @shutdown = false
      @queue = ArrayBlockingQueue.new(options[:queue_size] || 1000)
      @lock = java.lang.Object.new

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
      # The lock ensures that no new data can be added to the queue while
      # the shutdown flag is being set. Once the shutdown flag is set, it guards
      # handler.put and lets it return false immediately instead of blocking.
      @lock.synchronized do
        if @shutdown
          false
        else
          @queue.put(record)
          true
        end
      end
    end

    def flush
      @workers.map(&:flush)
    end

    def shutdown(block = false, duration = 2, unit = TimeUnit::SECONDS)
      # Only setting the flag needs to be synchronized. See the note in handle.
      @lock.synchronized do
        @shutdown = true
      end

      # Since each worker takes one queue item at a time and terminates after
      # taking a single shutdown token, putting N tokens in the queue for N
      # workers should shut down all N workers.
      @workers.size.times do
        @queue.put(AsyncHandlerWorker::SHUTDOWN)
      end

      @worker_pool.shutdown
      await(duration, unit) if block
    end

    def await(duration = 10, unit = TimeUnit::SECONDS)
      # NOTE: Once every worker exits,
      @worker_pool.await_termination(duration, unit)
    end
  end

  class ShutdownCommand; end

  class AsyncHandlerWorker
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
      Telekinesis.logger.error("Async producer thread died: #{e}")
    end

    def put_data(data)
      Producer.put_data(@client, @stream, data)
    end
  end
end
