require_relative 'test_helper'

java_import java.util.concurrent.TimeUnit
java_import java.util.concurrent.CountDownLatch
java_import java.util.zip.GZIPInputStream
java_import java.io.ByteArrayInputStream

class FakeClient
  attr_reader :queue

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
end

class ProducerTest < Minitest::Test
  context "producer" do
    setup do
      @worker_count = 2
      @poll_timeout = 200
      @client = FakeClient.new
      # NOTE: Set the poll interval so that the tests can use it. That's not super
      #       great, but it's better than hard coding them.
      handler_opts = {:poll_timeout => @poll_timeout, :worker_count => @worker_count}
      @handler = Telekinesis::Producer.new('test-stream', @client, handler_opts) do
        Telekinesis::DelimitedSerializer.new(100, "\n")
      end
    end

    should "actually shut down" do
      @client.start
      @handler.shutdown
      assert(@handler.await(2), "Expected producer to shut down within 2s")
    end

    should "not accept more events once shut down" do
      @client.start
      @handler.shutdown
      assert(!@handler.put("{}"))
    end

    should "batch data to the client" do
      @client.start
      # NOTE: With a 100 byte buffer, the serializer flushes on the 15th
      #       write, generating records that contain "banana\n" * 14. With two
      #       workers, have to put at least 30 records to get one to flush.
      30.times do
        @handler.put("banana")
      end

      request = @client.queue.take
      assert_equal('test-stream', request.stream_name)
      assert_equal("banana\n" * 14, ByteArrayInputStream.new(request.data.array).to_io.read)

      # Each worker thread should do a put at least every @poll_timeout milis.
      # Account for a little slop and then proceed.
      java.lang.Thread.sleep(@poll_timeout + 100)
      bananas = []
      @client.queue.each do |r|
        assert_equal('test-stream', r.stream_name)
        payload = ByteArrayInputStream.new(r.data.array).to_io.read
        assert_match(/^(banana\n)$/, payload)
        bananas += payload.split(/\n/)
      end
      assert_equal(["banana"] * (30 - 14), bananas)
    end

    should "flush after enough time has elapsed" do
      @client.start
      @handler.put("banana")

      java.lang.Thread.sleep(@poll_timeout + 100)
      request = @client.queue.take
      assert_equal('test-stream', request.stream_name)
      assert_equal("banana\n", ByteArrayInputStream.new(request.data.array).to_io.read)

      assert_nil(@client.queue.poll)
    end

    should "process all events in the queue before shutting down" do
      # NOTE: Don't start the fake client yet! All workers are now blocked on
      #       trying to submit 'whatever_nerd' to the client.
      @worker_count.times { @handler.put("whatever_nerd") }
      @results = ArrayBlockingQueue.new(1000)

      @handler.shutdown(false) # don't block
      assert(!@handler.put("u can't handle me"))

      @client.start
      assert(@handler.await(2, TimeUnit::SECONDS))

      nerds = []
      loop do
        request = @client.queue.poll
        break unless request
        nerds += ByteArrayInputStream.new(request.data.array).to_io.read.split(/\n/)
      end
      assert_equal(["whatever_nerd"] * @worker_count, nerds)
    end

    teardown do
      @handler.shutdown
      @handler = nil
      @client = nil
    end
  end
end
