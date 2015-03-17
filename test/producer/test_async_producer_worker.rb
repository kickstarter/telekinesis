require_relative '../test_helper'

require "telekinesis/producer/async_producer_worker"

java_import java.util.concurrent.TimeUnit
java_import java.util.concurrent.ArrayBlockingQueue


class AsyncProducerWorkerTest < Minitest::Test
  StubProducer = Struct.new(:stream, :client) do
    def on_failure(failures)
      @failures = failures
    end
  end

  StubResponse = Struct.new(:failed_record_count, :get_records)
  StubResponseEntry = Struct.new(:error_code)

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

  context "producer worker" do
    setup do
      @send_size = 10
      @send_every = 25
    end

    context "with no items in the queue" do
      setup do
        @producer = stub_producer('test')
        @queue = ArrayBlockingQueue.new(10)
        @worker = Telekinesis::AsyncProducerWorker.new(@producer, @queue, @send_size, @send_every)
        @worker_thread = Thread.new{ @worker.run }
      end

      teardown do
        @worker_thread.kill
      end

      should "not call put_records" do
        refute(@producer.client.results.poll(@send_every * 3, TimeUnit::MILLISECONDS))
      end
    end

    context "with only SHUTDOWN in the queue" do
      setup do
        @producer = stub_producer('test')
        @queue = ArrayBlockingQueue.new(10).tap do |q|
          q.put(Telekinesis::AsyncProducerWorker::SHUTDOWN)
        end
        @worker = Telekinesis::AsyncProducerWorker.new(@producer, @queue, @send_size, @send_every)
        @worker_thread = Thread.new{ @worker.run }
      end

      should "shut down the worker" do
        assert(@worker_thread.join((@send_every * 1000).to_f))
      end
    end

    context "with [item, SHUTDOWN] in the queue" do
      setup do
        @producer = stub_producer('test')
        @queue = ArrayBlockingQueue.new(10).tap do |q|
          q.put(["key", "value"])
          q.put(Telekinesis::AsyncProducerWorker::SHUTDOWN)
        end
        @worker = Telekinesis::AsyncProducerWorker.new(@producer, @queue, @send_size, @send_every)
        @worker_thread = Thread.new{ @worker.run }
      end

      should "put data before shutting down the worker" do
        assert(@worker_thread.join((@send_every * 1000).to_f), "worker should shut down")

        request, = @producer.client.results.to_a
        assert_equal(request.stream_name, 'test',
                     "request should have the correct stream name")
        assert_equal([["key", "value"]],
                     request.records.map{|r| [r.partition_key, string_from_bytebuffer(r.data)]},
                     "Payload should be a nested array")
      end
    end

    context "with fewer than send_size items in queue" do
      should "send one request" do
        assert false
      end
    end

    context "with more than send_size items in queue" do
      should "send multiple requests of at most send_size" do
        assert false
      end
    end

    context "when requests fail" do
      should "call the producer with all failed requests" do
        assert false
      end
    end
  end
end
