require "telekinesis/producer/util"
require "telekinesis/producer/async_producer_worker"

java_import java.util.concurrent.TimeUnit
java_import java.util.concurrent.Executors
java_import java.util.concurrent.ArrayBlockingQueue
java_import com.google.common.util.concurrent.ThreadFactoryBuilder

module Telekinesis
  class AsyncProducer
    attr_reader :stream, :client

    def initialize(stream, client, options = {})
      @stream = stream
      @client = client
      @shutdown = false
      @queue = ArrayBlockingQueue.new(options[:queue_size] || 1000)
      @lock = Util::ReadWriteLock.new

      send_every   = options[:send_every_ms] || 1000
      worker_count = options[:worker_count] || 3

      # Create workers outside of pool.submit so that the handler can keep
      # a reference to each worker for calls to flush and shutdown.
      @worker_pool = build_executor(worker_count)
      @workers = worker_count.times.map do
        AsyncProducerWorker.new(self, @queue, send_every)
      end
      @workers.each do |w|
        @worker_pool.java_send(:submit, [java.lang.Runnable.java_class], w)
      end
    end

    def put(key, data)
      # NOTE: The lock ensures that no new data can be added to the queue after
      # the shutdown flag has been set. See the note in shutdown for details.
      # NOTE: Since this is a read lock, multiple threads can `put` data at the
      # same time without blocking on each other.
      @lock.read_lock do
        if @shutdown
          false
        else
          @queue.put([key, data])
          true
        end
      end
    end

    def on_failure(failures)
      Telekinesis.logger.error("put_records returned #{failures.size} failures")
    end

    def shutdown(block = false, duration = 2, unit = TimeUnit::SECONDS)
      # NOTE: Since a write_lock is exclusive, this prevents any data from being
      # added to the queue while the SHUTDOWN tokens are being inserted. Without
      # the lock, data can end up in the queue behind all of the shutdown tokens
      # and be lost. This happens if the shutdown flag is be flipped by a thread
      # calling shutdown after another thread has checked the "if @shutdown"
      # condition in put but before it's called queue.put.
      @lock.write_lock do
        @shutdown = true
        @workers.size.times do
          @queue.put(ProducerWorker::SHUTDOWN)
        end
      end

      # Don't interrupt workers by calling shutdown_now.
      @worker_pool.shutdown
      await(duration, unit) if block
    end

    def await(duration, unit = TimeUnit::SECONDS)
      @worker_pool.await_termination(duration, unit)
    end

    def queue_size
      @queue.size
    end

    protected

    def build_executor(worker_count)
      Executors.new_fixed_thread_pool(
        worker_count,
        ThreadFactoryBuilder.new.set_name_format("#{stream}-producer-worker-%d").build
      )
    end
  end
end
