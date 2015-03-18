require_relative '../test_helper'

require "telekinesis/producer/async_producer_worker"

java_import java.util.concurrent.TimeUnit
java_import java.util.concurrent.ArrayBlockingQueue

class AsyncProducerWorkerTest < Minitest::Test
  StubProducer = Struct.new(:stream, :client) do
    attr_reader :failures

    def on_failure(failures)
      @failures = failures
    end
  end

  StubResponse = Struct.new(:failed_record_count, :records)
  StubResponseEntry = Struct.new(:error_code) do
    def error_message
      "potato"
    end
  end

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
    attr_reader :results

    def initialize(responses)
      @results = ArrayBlockingQueue.new(1000)
      @responses = responses
    end

    def put_records(request)
      @results.put(request)
      @responses.shift || StubResponse.new(0, [])
    end
  end

  def stub_producer(stream, *responses)
    StubProducer.new(stream, CapturingClient.new(responses))
  end

  # NOTE: This always adds SHUTDOWN to the end of the list so that the worker
  # can be run in the test thread and there's no need to deal with coordination
  # across multiple threads. To simulate the worker timing out on a queue.poll
  # just add 'nil' to your list of items in the queue at the appropriate place.
  def queue_with(*items)
    to_put = items + [Telekinesis::AsyncProducerWorker::SHUTDOWN]
    StubQueue.new(to_put)
  end

  def build_worker
    Telekinesis::AsyncProducerWorker.new(@producer, @queue, @send_size, @send_every)
  end

  def records_as_kv_pairs(request)
    request.records.map{|r| [r.partition_key, string_from_bytebuffer(r.data)]}
  end

  context "producer worker" do
    setup do
      @send_size = 10
      @send_every = 100 # ms
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
        request, = @producer.client.results.to_a
        assert_equal(request.stream_name, 'test', "request should have the correct stream name")
        assert_equal([["key", "value"]], records_as_kv_pairs(request), "Request payload should be kv pairs")
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
        request, = @producer.client.results.to_a
        assert(request, "should produce data")
        assert_equal('test', request.stream_name, "request should have the correct stream name")
        assert_equal(@items, records_as_kv_pairs(request), "Request payload should be kv pairs")
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
        request, = @producer.client.results.to_a
        assert_equal('test', request.stream_name, "request should have the correct stream name")
        assert_equal(@items, records_as_kv_pairs(request), "Request payload should be kv pairs")
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

        requests = @producer.client.results.to_a.each
        expected = @items.each_slice(@send_size).to_a

        expected.zip(requests) do |kv_pairs, request|
          assert_equal('test', request.stream_name, "Request should have the correct stream name")
          assert_equal(kv_pairs, records_as_kv_pairs(request), "Request payload should be kv pairs")
        end
      end
    end

    context "when some records return an error response" do
      setup do
        num_items = @send_size - 1
        @items = num_items.times.map{|i| ["key-#{i}", "value-#{i}"]}
        @response_entries = num_items.times.map do |i|
          if i.even?
            StubResponseEntry.new("code-#{i}")
          else
            StubResponseEntry.new
          end
        end
        @expected_failures = @items.zip(@response_entries)
                                   .reject{|_, entry| entry.error_code.nil?}
                                   .map{|item, _| item}

        @producer = stub_producer('test', StubResponse.new(@response_entries.size, @response_entries))
        @queue = queue_with(*@items)
        @worker = build_worker
      end

      should "call the producer with all failed records" do
        @worker.run
        assert_equal(@expected_failures, @producer.failures.map{|k, v, _, _| [k, v]})
      end
    end

    # TODO: test for AWS client exceptions
  end
end
