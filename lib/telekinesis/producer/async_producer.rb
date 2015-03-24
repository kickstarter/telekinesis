require "telekinesis/producer/util"
require "telekinesis/producer/async_producer_worker"

java_import java.util.concurrent.TimeUnit
java_import java.util.concurrent.Executors
java_import java.util.concurrent.ArrayBlockingQueue
java_import com.google.common.util.concurrent.ThreadFactoryBuilder

module Telekinesis
  class AsyncProducer
    # NOTE: This isn't configurable right now because it's a Kinesis API limit.
    # TODO: Set an option to lower this.
    # FIXME: Move this into KinesisUtils or something. Used in two places.
    MAX_PUT_RECORDS_SIZE = 500

    attr_reader :stream, :client

    def initialize(stream, client, options = {})
      @stream = stream
      @client = client
      @shutdown = false

      queue_size   = options.fetch(:queue_size, 1000)
      send_every   = options.fetch(:send_every_ms, 1000)
      worker_count = options.fetch(:worker_count, 3)
      send_size    = options.fetch(:send_size, MAX_PUT_RECORDS_SIZE)
      raise ArgumentError("buffer_size too large") if send_size > MAX_PUT_RECORDS_SIZE

      # NOTE: Primarily for testing.
      @queue = options[:queue] || ArrayBlockingQueue.new(queue_size)

      @lock = Util::ReadWriteLock.new
      @worker_pool = build_executor(worker_count)
      @workers = worker_count.times.map do
        AsyncProducerWorker.new(self, @queue, send_size, send_every)
      end

      # NOTE: Primarily for testing. Start by default.
      start unless options.fetch(:manual_start, true)
    end

    def start
      @workers.each do |w|
        @worker_pool.java_send(:submit, [java.lang.Runnable.java_class], w)
      end
    end

    def put(key, data)
      # NOTE: The lock ensures that no new data can be added to the queue after
      # the shutdown flag has been set. See the note in shutdown for details.
      # NOTE: Since this is a read lock, multiple threads can `put` data at the
      # same time without blocking on each other.
      # TODO: is there a try_read_lock? the only time this blocks is if the
      # producer is shutting down.
      @lock.read_lock do
        if @shutdown
          false
        else
          @queue.put([key, data])
          true
        end
      end
    end

    def put_all(items)
      # NOTE: Doesn't delegate to put so that shutdown can't cause a call to
      # put_all to only enqueue some items.
      # NOTE: see the note in put for information about this read_lock.
      @lock.read_lock do
        if @shutdown
          false
        else
          items.each do |key, data|
            @queue.put([key, data])
          end
          true
        end
      end
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
          @queue.put(AsyncProducerWorker::SHUTDOWN)
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

    # Callbacks. These all default to noops.
    #
    # Callbacks are all called from background worker threads when that worker
    # encounters a failure. These callbacks must all be thread-safe.

    def on_record_failure(failed_records); end
    def on_kinesis_retry(error); end
    def on_kinesis_failure(error); end

    protected

    def build_executor(worker_count)
      Executors.new_fixed_thread_pool(
        worker_count,
        ThreadFactoryBuilder.new.set_name_format("#{stream}-producer-worker-%d").build
      )
    end
  end
end
