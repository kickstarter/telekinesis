require_relative '../test_helper'

require "telekinesis/producer/async_producer"

java_import java.util.concurrent.TimeUnit
java_import java.util.concurrent.CountDownLatch
java_import java.util.concurrent.ArrayBlockingQueue


class AsyncProducerWorkerTest < Minitest::Test
  StubProducer = Struct.new(:stream, :client)
  StubResponse = Struct.new(:failed_record_count, :get_records)

  class CapturingClient
    attr_reader :results

    def initialize(responses)
      @results = ArrayBlockingQueue.new(1000)
      @responses = responses
    end

    def put_records(request)
      @results.puts(request)
      @responses.shift
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

    context "with no items in a queue" do
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

    context "with a shutdown item in the queue" do
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
  end
end
