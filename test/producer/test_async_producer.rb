require_relative "test_helper"

class AsyncProducerTest < Minitest::Test
  java_import java.util.concurrent.CountDownLatch
  java_import java.util.concurrent.ArrayBlockingQueue

  StubClient = Struct.new(:welp)

  class LatchQueue
    def initialize
      @under = ArrayBlockingQueue.new(100)
      @latch = CountDownLatch.new(1)
      @putting = CountDownLatch.new(1)
    end

    def count_down
      @latch.count_down
    end

    def wait_for_put
      @putting.await
    end

    def put(item)
      @putting.count_down
      @latch.await
      @under.put(item)
    end
  end

  def build_producer
    opts = {
      queue: @queue,
      manual_start: true,
      worker_count: @worker_count,
    }
    Telekinesis::Producer::AsyncProducer.new(
      @stream,
      StubClient.new,
      Telekinesis::Producer::NoopFailureHandler.new,
      opts
    )
  end

  context "AsyncProducer" do
    setup do
      @stream = 'test'  # ignored
      @worker_count = 3 # arbitrary
    end

    context "put" do
      setup do
        @queue = ArrayBlockingQueue.new(100)
        build_producer.put("hi", "there")
      end

      should "add the k,v pair to the queue" do
        assert_equal([["hi", "there"]], @queue.to_a)
      end
    end

    context "put_all" do
      setup do
        @items = 10.times.map{|i| ["key-#{i}", "value-#{i}"]}
        @queue = ArrayBlockingQueue.new(100)
        build_producer.put_all(@items)
      end

      should "add all items to the queue" do
        assert_equal(@items, @queue.to_a)
      end
    end

    context "after shutdown" do
      setup do
        @queue = ArrayBlockingQueue.new(100)
        @producer = build_producer
        @producer.shutdown
      end

      should "shutdown all workers" do
        assert_equal([Telekinesis::Producer::AsyncProducerWorker::SHUTDOWN] * @worker_count, @queue.to_a)
      end

      should "not accept events while shut down" do
        refute(@producer.put("key", "value"))
      end
    end

    context "with a put in progress" do
      setup do
        @queue = LatchQueue.new
        @producer = build_producer

        # Thread blocks waiting for the latch in LatchQueue. Don't do any other
        # set up until this thread is in the critical section.
        Thread.new do
          @producer.put("k", "v")
        end
        @queue.wait_for_put

        # Thread blocks waiting for the write_lock in AsyncProducer. Once it's
        # unblocked it signals by counting down shutdown_latch.
        @shutdown_latch = CountDownLatch.new(1)
        Thread.new do
          @producer.shutdown
          @shutdown_latch.count_down
        end
      end

      should "block on shutdown until the put is done" do
        # Check that the latch hasn't been triggered yet. Return immediately
        # from the check - don't bother waiting.
        refute(@shutdown_latch.await(0, TimeUnit::MILLISECONDS))
        @queue.count_down
        # NOTE: The assert is here to fail the test if it times out. This could
        # effectively just be an await with no duration.
        assert(@shutdown_latch.await(2, TimeUnit::SECONDS))
      end
    end

    context "with a shutdown in progress" do
      setup do
        @queue = LatchQueue.new
        @producer = build_producer

        # Thread blocks waiting to insert :shutdown into the queue because of
        # the latch in LatchQueue. Don't do any other test set up until this
        # thread is in the critical section.
        Thread.new do
          @producer.shutdown
        end
        @queue.wait_for_put

        # This thread blocks waiting for the lock in AsyncProducer. Once it's
        # done the put continues and then it signals completion by counting
        # down finished_put_latch.
        @finished_put_latch = CountDownLatch.new(1)
        Thread.new do
          @put_result = @producer.put("k", "v")
          @finished_put_latch.count_down
        end
      end

      should "block on a put" do
        # Thread is already waiting in the critical section. Just check that
        # the call hasn't exited yet and return immediately.
        refute(@finished_put_latch.await(0, TimeUnit::MILLISECONDS))
        @queue.count_down
        # NOTE: The assert is here to fail the test if it times out. This could
        # effectively just be an await with no duration.
        assert(@finished_put_latch.await(2, TimeUnit::SECONDS))
        refute(@put_result, "Producer should reject a put after shutdown")
      end
    end
  end
end
