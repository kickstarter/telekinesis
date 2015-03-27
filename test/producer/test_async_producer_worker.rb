require_relative "test_helper"

class AsyncProducerWorkerTest < Minitest::Test
  java_import java.util.concurrent.TimeUnit
  java_import java.util.concurrent.ArrayBlockingQueue

  def string_from_bytebuffer(bb)
    String.from_java_bytes bb.array
  end

  class CapturingFailureHandler
    attr_reader :retries, :final_err

    def initialize
      @retries = 0
    end

    def failed_records
      @failed_records ||= []
    end

    def on_record_failure(fails)
      failed_records << fails
    end

    def on_kinesis_retry(error, items)
      @retries += 1
    end

    def on_kinesis_failure(error, items)
      @final_err = [error, items]
    end
  end

  StubProducer = Struct.new(:stream, :client, :failure_handler)

  # NOTE: This stub mocks the behavior of timing out on poll once all of the
  # items have been drained from the internal list.
  class StubQueue
    def initialize(items)
      @items = items
    end

    def poll(duration, unit)
      @items.shift
    end
  end

  class CapturingClient
    attr_reader :requests

    def initialize(responses)
      @requests = ArrayBlockingQueue.new(1000)
      @responses = responses
    end

    def put_records(stream, items)
      @requests.put([stream, items])
      @responses.shift || []
    end
  end

  class ExplodingClient
    def initialize(exception)
      @exception = exception
    end

    def put_records(stream, items)
      raise @exception
    end
  end

  def stub_producer(stream, responses = [])
    StubProducer.new(stream, CapturingClient.new(responses), CapturingFailureHandler.new)
  end

  # NOTE: This always adds SHUTDOWN to the end of the list so that the worker
  # can be run in the test thread and there's no need to deal with coordination
  # across multiple threads. To simulate the worker timing out on a queue.poll
  # just add 'nil' to your list of items in the queue at the appropriate place.
  def queue_with(*items)
    to_put = items + [Telekinesis::Producer::AsyncProducerWorker::SHUTDOWN]
    StubQueue.new(to_put)
  end

  def build_worker
    Telekinesis::Producer::AsyncProducerWorker.new(
      @producer,
      @queue,
      @send_size,
      @send_every,
      @retries,
      @retry_interval
    )
  end

  def records_as_kv_pairs(request)
    request.records.map{|r| [r.partition_key, string_from_bytebuffer(r.data)]}
  end

  context "producer worker" do
    setup do
      @send_size = 10
      @send_every = 100 # ms
      @retries = 2
      @retry_interval = 0.01
    end

    context "with only SHUTDOWN in the queue" do
      setup do
        @producer = stub_producer('test')
        @queue = queue_with() # shutdown is always added
        @worker = build_worker
      end

      should "shut down the worker" do
        Timeout.timeout(0.1){@worker.run}
        assert(@worker.instance_variable_get(:@shutdown))
      end
    end

    context "with [item, SHUTDOWN] in the queue" do
      setup do
        @producer = stub_producer('test')
        @queue = queue_with(
          ["key", "value"],
        )
        @worker = build_worker
      end

      should "put data before shutting down the worker" do
        Timeout.timeout(0.1){@worker.run}
        stream, items = @producer.client.requests.first
        assert_equal(stream, 'test', "request should have the correct stream name")
        assert_equal([["key", "value"]], items, "Request payload should be kv pairs")
      end
    end

    context "with buffered data that times out" do
      setup do
        @items = [["key", "value"]]

        @producer = stub_producer('test')
        # Explicitly add 'nil' to fake the queue being empty
        @queue = queue_with(*(@items + [nil]))
        @worker = build_worker
      end

      should "send whatever is in the queue" do
        @worker.run
        stream, items = @producer.client.requests.first
        assert_equal('test', stream, "request should have the correct stream name")
        assert_equal(items, @items, "Request payload should be kv pairs")
      end
    end

    context "with fewer than send_size items in queue" do
      setup do
        num_items = @send_size - 1
        @items = num_items.times.map{|i| ["key-#{i}", "value-#{i}"]}

        @producer = stub_producer('test')
        @queue = queue_with(*@items)
        @worker = build_worker
      end

      should "send one request" do
        Timeout.timeout(0.1){@worker.run}
        stream, items = @producer.client.requests.first
        assert_equal('test', stream, "request should have the correct stream name")
        assert_equal(@items, items, "Request payload should be kv pairs")
      end
    end

    context "with more than send_size items in queue" do
      setup do
        num_items = (@send_size * 2) - 1
        @items = num_items.times.map{|i| ["key-#{i}", "value-#{i}"]}

        @producer = stub_producer('test')
        @queue = queue_with(*@items)
        @worker = build_worker
      end

      should "send multiple requests of at most send_size" do
        Timeout.timeout(0.1){@worker.run}
        expected = @items.each_slice(@send_size).to_a
        expected.zip(@producer.client.requests) do |kv_pairs, (stream, batch)|
          assert_equal('test', stream, "Request should have the correct stream name")
          assert_equal(batch, kv_pairs, "Request payload should be kv pairs")
        end
      end
    end

    context "when some records return an error response" do
      setup do
        num_items = @send_size - 1
        @items = num_items.times.map{|i| ["key-#{i}", "value-#{i}"]}
        @failed_items = @items.each_with_index.map do |item, idx|
          if idx.even?
            k, v = item
            [k, v, "code", "message"]
          else
            nil
          end
        end
        @failed_items.compact!

        @producer = stub_producer('test', [@failed_items])
        @queue = queue_with(*@items)
        @worker = build_worker
      end

      should "call the producer with all failed records" do
        @worker.run
        assert_equal([@failed_items], @producer.failure_handler.failed_records)
      end
    end

    context "when the client throws an exception" do
      setup do
        @boom = Telekinesis::Aws::KinesisError.new(com.amazonaws.AmazonClientException.new("boom"))
        @producer = StubProducer.new(
          'stream',
          ExplodingClient.new(@boom),
          CapturingFailureHandler.new
        )
        @queue = queue_with(['foo', 'bar'])
        @worker = build_worker
      end

      should "call the failure handler on retries and errors" do
        @worker.run
        assert_equal((@retries - 1), @producer.failure_handler.retries)
        err, items = @producer.failure_handler.final_err
        assert_equal(@boom, err)
        assert_equal([['foo', 'bar']], items)
      end
    end
  end
end
