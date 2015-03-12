require "telekinesis/producer/worker"
require "telekinesis/producer/worker_two"
require "telekinesis/producer/serializer"

java_import java.util.concurrent.TimeUnit
java_import com.google.common.hash.Hashing
java_import java.util.concurrent.Executors
java_import java.util.concurrent.ArrayBlockingQueue
java_import com.google.common.util.concurrent.ThreadFactoryBuilder

module Telekinesis
  ##
  # A high-level producer for records that should be batched together before
  # being sent to Kinesis. Assumes that batches of records should be
  # distributed evenly across the shards in a stream.
  #
  # This class is thread-safe.
  #
  # NOTE: No low-level stats are kept on calls to producer.put, and no background
  #       threads tracking the size of the queue are started. The user is
  #       responsible for instrumenting those high-level details at whatever
  #       granularity they want to. Instead, the `queue_size` hook is provided.
  #       Put latency and count can be measured externally.
  class Producer
    MURMUR_3_128 = Hashing.murmur3_128()

    attr_reader :stream, :use_put_records

    def initialize(stream, client, options = {}, &block)
      @stream = stream
      @client = client
      @shutdown = false
      @queue = ArrayBlockingQueue.new(options[:queue_size] || 1000)
      @lock = java.lang.Object.new

      # Create workers outside of pool.submit so that the handler can keep
      # a reference to each worker for calls to flush and shutdown.
      @use_put_records = options[:use_put_records] || false
      @poll_timeout    = options[:poll_timeout] || 1000
      worker_count     = options[:worker_count] || 3

      @workers = worker_count.times.map do
        build_worker(&block)
      end

      thread_factory = ThreadFactoryBuilder.new.set_name_format("#{stream}-handler-worker-%d").build
      @worker_pool = Executors.new_fixed_thread_pool(worker_count, thread_factory)
      @workers.each{ |w| @worker_pool.java_send(:submit, [java.lang.Runnable.java_class], w) }
    end

    def build_worker(&block)
      if use_put_records
        ProducerWorkerTwo.new(@stream, @queue, @client, @poll_timeout)
      else
        raise ArgumentError if !block_given?
        ProducerWorker.new(@stream, @queue, @client, @poll_timeout, block.call)
      end
    end

    def put(record)
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

    def shutdown(block = false, duration = 2, unit = TimeUnit::SECONDS)
      # Only setting the flag needs to be synchronized. See the note in handle.
      @lock.synchronized do
        @shutdown = true
      end

      # Since each worker takes one queue item at a time and terminates after
      # taking a single shutdown token, putting N tokens in the queue for N
      # workers should shut down all N workers.
      @workers.size.times do
        @queue.put(ProducerWorker::SHUTDOWN)
      end

      @worker_pool.shutdown
      await(duration, unit) if block
    end

    def await(duration = 10, unit = TimeUnit::SECONDS)
      # NOTE: Once every worker exits,
      @worker_pool.await_termination(duration, unit)
    end

    def queue_size
      @queue.size
    end
  end
end
