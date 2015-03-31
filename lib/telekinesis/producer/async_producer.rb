require "telekinesis/producer/async_producer_worker"

module Telekinesis
  module Producer
    java_import java.util.concurrent.TimeUnit
    java_import java.util.concurrent.Executors
    java_import java.util.concurrent.ArrayBlockingQueue
    java_import com.google.common.util.concurrent.ThreadFactoryBuilder

    # An asynchronous producer that buffers events into a queue and uses a
    # background thread to send them to Kinesis. Only available on JRuby.
    #
    # This class is thread-safe.
    class AsyncProducer
      # For convenience
      MAX_PUT_RECORDS_SIZE = Telekinesis::Aws::KINESIS_MAX_PUT_RECORDS_SIZE

      attr_reader :stream, :client, :failure_handler

      # Create a new producer.
      #
      # AWS credentials may be specified by using the `:credentials` option and
      # passing a hash containing your `:access_key_id` and `:secret_access_key`.
      # If unspecified, credentials will be fetched from the environment, an
      # ~/.aws/credentials file, or the current instance metadata.
      #
      # The producer's `:worker_count`, internal `:queue_size`, the `:send_size`
      # of batches to Kinesis and how often workers send data to Kinesis, even
      # if their batches aren't full (`:send_every_ms`) can be configured as
      # well. They all have reasonable defaults.
      #
      # When requests to Kinesis fail, the configured `:failure_handler` will
      # be called. If you don't specify a failure handler, a NoopFailureHandler
      # is used.
      def self.create(options = {})
        stream = options[:stream]
        client = Telekinesis::Aws::Client.build(options.fetch(:credentials, {}))
        failure_handler = options.fetch(:failure_handler, NoopFailureHandler.new)
        new(stream, client, failure_handler, options)
      end

      # NOTE: You should use #create unless you know what you're doing.
      def initialize(stream, client, failure_handler, options = {})
        @stream = stream or raise ArgumentError, "stream may not be nil"
        @client = client or raise ArgumentError, "client may not be nil"
        @failure_handler = failure_handler or raise ArgumentError, "failure_handler may not be nil"
        @shutdown = false

        queue_size     = options.fetch(:queue_size, 1000)
        send_every     = options.fetch(:send_every_ms, 1000)
        worker_count   = options.fetch(:worker_count, 1)
        raise ArgumentError(":worker_count must be > 0") unless worker_count > 0
        send_size      = options.fetch(:send_size, MAX_PUT_RECORDS_SIZE)
        raise ArgumentError(":send_size too large") if send_size > MAX_PUT_RECORDS_SIZE
        retries        = options.fetch(:retries, 5)
        raise ArgumentError(":retries must be >= 0") unless retries >= 0
        retry_interval = options.fetch(:retry_interval, 1.0)
        raise ArgumentError(":retry_interval must be > 0") unless retry_interval > 0

        # NOTE: For testing.
        @queue = options[:queue] || ArrayBlockingQueue.new(queue_size)

        @lock = Telekinesis::JavaUtil::ReadWriteLock.new
        @worker_pool = build_executor(worker_count)
        @workers = worker_count.times.map do
          AsyncProducerWorker.new(self, @queue, send_size, send_every, retries, retry_interval)
        end

        # NOTE: Start by default. For testing.
        start unless options.fetch(:manual_start, false)
      end

      # Put a single key, value pair to Kinesis. Both key and value must be
      # strings.
      #
      # This call returns immediately and returns true iff the producer is still
      # accepting data. Data is put to Kinesis in the background.
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

      # Put all of the given key, value pairs to Kinesis. Both key and value
      # must be Strings.
      #
      # This call returns immediately and returns true iff the producer is still
      # accepting data. Data is put to Kinesis in the background.
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

      # Shut down this producer. After the call completes, the producer will not
      # accept any more data, but will finish processing any data it has
      # buffered internally.
      #
      # If block = true is passed, this call will block and wait for the producer
      # to shut down before returning. This wait times out after duration has
      # passed.
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

      # Wait for this producer to shutdown.
      def await(duration, unit = TimeUnit::SECONDS)
        @worker_pool.await_termination(duration, unit)
      end

      # Return the number of events currently buffered by this producer. This
      # doesn't include any events buffered in workers that are currently on
      # their way to Kinesis.
      def queue_size
        @queue.size
      end

      protected

      def start
        @workers.each do |w|
          @worker_pool.java_send(:submit, [java.lang.Runnable.java_class], w)
        end
      end

      def build_executor(worker_count)
        Executors.new_fixed_thread_pool(
          worker_count,
          ThreadFactoryBuilder.new.set_name_format("#{stream}-producer-worker-%d").build
        )
      end
    end
  end
end
