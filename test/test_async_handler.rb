require_relative 'test_helper'

java_import java.util.concurrent.TimeUnit
java_import java.util.concurrent.CountDownLatch
java_import java.util.zip.GZIPInputStream
java_import java.io.ByteArrayInputStream

class FakeClient
  def initialize
    @queue = ArrayBlockingQueue.new(100)
    @latch = CountDownLatch.new(1)
  end

  def start
    @latch.count_down
  end

  def put_record(request)
    @latch.await
    @queue.put(request)
  end

  def get_next_request(duration = 5, unit = TimeUnit::SECONDS)
    @queue.poll(duration, unit)
  end
end

class AsyncHanlderTest < Minitest::Test
  context "async handler" do
    setup do
      @worker_count = 2
      @poll_timeout = 500
      @client = FakeClient.new
      # NOTE: Set the poll interval so that the tests can use it. That's not super
      #       great, but it's better than hard coding them.
      handler_opts = {:poll_timeout => @poll_timeout, :worker_count => @worker_count}
      @handler = Telekinesis::AsyncHandler.new('test-stream', @client, handler_opts) do
        Telekinesis::GZIPDelimitedSerializer.new(100, "\n")
      end
    end

    should "actually shut down" do
      @client.start
      @handler.shutdown
      assert(@handler.await(2), "Expected handler to shut down within 2s")
    end

    should "flush data" do
      @client.start
      assert(@handler.handle("{}"))
      assert_nil(@client.get_next_request(@poll_timeout * 2, TimeUnit::MILLISECONDS))

      @handler.flush
      request = @client.get_next_request(@poll_timeout * 2, TimeUnit::MILLISECONDS)
      assert_equal('test-stream', request.stream_name)
    end

    should "not accept more events once shut down" do
      @client.start
      @handler.shutdown
      assert(!@handler.handle("{}"))
    end

    should "batch data to the client" do
      @client.start
      # NOTE: With a 100 byte buffer, the gzip serializer flushes on the 10th
      #       write, generating records that contain "banana\n" * 9.
      #       18 writes should generate at least 1 request
      19.times do
        @handler.handle("banana")
      end

      request = @client.get_next_request(@poll_timeout * 2, TimeUnit::MILLISECONDS)
      assert_equal('test-stream', request.stream_name)
      assert_equal("banana\n" * 9,
                   GZIPInputStream.new(ByteArrayInputStream.new(request.data.array)).to_io.read)

      @handler.flush
      request = @client.get_next_request(@poll_timeout * 2, TimeUnit::MILLISECONDS)
      assert_equal('test-stream', request.stream_name)
      assert_match(/^(banana\n)$/,
                   GZIPInputStream.new(ByteArrayInputStream.new(request.data.array)).to_io.read)
    end

    should "drain all events in the queue" do
      # NOTE: Don't start the fake client yet! All workers are now blocked on
      #       trying to submit 'whatever_nerd' to the client.
      @worker_count.times { @handler.handle("whatever_nerd") }
      @results = ArrayBlockingQueue.new(1000)

      # Drain in a background thread. Use a latch to signal to the test thread
      # that the drain is done, and send the results back using another queue.
      drain_thread_started = CountDownLatch.new(1)
      drain_finished = CountDownLatch.new(1)
      Thread.new {
        drain_thread_started.count_down
        @results.add_all(@handler.drain(5, 1, TimeUnit::SECONDS))
        drain_finished.count_down
      }

      # While the drain is going, check that no new items can be added.
      # NOTE: The loop is neccessary to prevent non-deterministc test failures.
      #       If the check for shutdown isn't done it's possible for the assert
      #       on @handler.handle to execute before the @handler.drain call is
      #       made.
      drain_thread_started.await
      loop do
        break if @handler.instance_variable_get(:@shutdown).get
      end
      assert(!@handler.handle("u can't handle me"))
      assert(drain_finished.count > 0)

      # Unblock workers so the drain can finish, make sure there's nothing in
      # the queue.
      @client.start
      drain_finished.await
      assert_nil(@results.poll)
    end

    teardown do
      @handler.shutdown
      @handler = nil
      @client = nil
    end
  end
end
