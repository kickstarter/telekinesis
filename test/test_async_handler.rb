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
        Telekinesis::DelimitedSerializer.new(100, "\n")
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
      # NOTE: With a 100 byte buffer, the serializer flushes on the 15th
      #       write, generating records that contain "banana\n" * 14. With two
      #       workers, have to put at least 30 records to get one to flush.
      30.times do
        @handler.handle("banana")
      end

      request = @client.get_next_request(@poll_timeout * 2, TimeUnit::MILLISECONDS)
      assert_equal('test-stream', request.stream_name)
      assert_equal("banana\n" * 14, ByteArrayInputStream.new(request.data.array).to_io.read)

      @handler.flush

      bananas = []
      loop do
        request = @client.get_next_request(@poll_timeout * 2, TimeUnit::MILLISECONDS)
        break unless request
        assert_equal('test-stream', request.stream_name)
        payload = ByteArrayInputStream.new(request.data.array).to_io.read
        assert_match(/^(banana\n)$/, payload)
        bananas += payload.split(/\n/)
      end
      assert_equal(30 - 14, bananas.size)
    end

    should "process all events in the queue before shutting down" do
      # NOTE: Don't start the fake client yet! All workers are now blocked on
      #       trying to submit 'whatever_nerd' to the client.
      @worker_count.times { @handler.handle("whatever_nerd") }
      @results = ArrayBlockingQueue.new(1000)

      @handler.shutdown(false) # don't block
      assert(!@handler.handle("u can't handle me"))

      @client.start
      assert(@handler.await(2, TimeUnit::SECONDS))

      nerds = []
      loop do
        request = @client.get_next_request(1, TimeUnit::MILLISECONDS)
        break unless request
        nerds += ByteArrayInputStream.new(request.data.array).to_io.read.split(/\n/)
      end
      assert_equal(nerds.size, @worker_count)
    end

    teardown do
      @handler.shutdown
      @handler = nil
      @client = nil
    end
  end
end
