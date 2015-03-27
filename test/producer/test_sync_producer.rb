require_relative "test_helper"


class SyncProducerTest < Minitest::Test
  StubPutRecordResponse = Struct.new(:shard_id, :sequence_number, :error_code, :error_message)

  class StubClient
    attr_reader :requests

    def initialize(*responses)
      @requests = []
      @responses = responses
    end

    def put_record(stream, key, value)
      @requests << [stream, [key, value]]
      @responses.shift || []
    end

    def put_records(stream, items)
      @requests << [stream, items]
      @responses.shift || []
    end
  end

  class TestingProducer < Telekinesis::Producer::SyncProducer
    def failures
      @failures ||= []
    end

    def on_record_failure(fs)
      failures << fs
    end
  end

  context "SyncProducer" do
    context "#put" do
      setup do
        @expected_response = StubPutRecordResponse.new(123, 123)
        @client = StubClient.new(@expected_response)
        @producer = TestingProducer.new('stream', @client)
      end

      should "call the underlying client's put_record" do
        assert(@producer.failures.empty?)
        assert_equal(@expected_response, @producer.put('key', 'value'))
        assert_equal(['stream', ['key', 'value']], @client.requests.first)
      end
    end

    context "#put_all" do
      context "with an empty argument" do
        setup do
          @client = StubClient.new([])
          @producer = TestingProducer.new('stream', @client)
          @actual_failures = @producer.put_all([])
        end

        should "send no data" do
          assert(@client.requests.empty?)
          assert(@actual_failures.empty?)
        end
      end

      context "with an argument smaller than :send_size" do
        setup do
          @send_size = 30
          @items = (@send_size - 1).times.map{|i| ["key-#{i}", "value-#{i}"]}
        end

        context "when no records fail" do
          setup do
            @client = StubClient.new([])
            @producer = TestingProducer.new('stream', @client, {send_size: @send_size})
            @actual_failures = @producer.put_all(@items)
          end

          should "send one batch and return nothing" do
            assert(@actual_failures.empty?)
            assert_equal([['stream', @items]], @client.requests)
          end
        end

        context "when some records fail" do
          setup do
            @client = StubClient.new([["key-2", "value-2", "fake error", "message"]])
            @producer = TestingProducer.new('stream', @client, {send_size: @send_size})
            @actual_failures = @producer.put_all(@items)
          end

          should "call on_record_failure" do
            assert_equal([['stream', @items]], @client.requests)
            assert_equal([["key-2", "value-2", "fake error", "message"]], @actual_failures)
          end
        end
      end

      context "with an argument larger than :send_size" do
        setup do
          @send_size = 30
          @items = (@send_size + 3).times.map{|i| ["key-#{i}", "value-#{i}"]}
          # expected_requests looks like:
          # [
          #   ['stream', [[k1, v1], [k2, v2], ...]],
          #   ['stream', [[kn, vn], [k(n+1), v(n+1)], ...]]
          # ]
          @expected_requests = @items.each_slice(@send_size).map{|batch| ['stream', batch]}
        end

        context "when no records fail" do
          setup do
            @client = StubClient.new([])
            @producer = TestingProducer.new('stream', @client, {send_size: @send_size})
            @actual_failures = @producer.put_all(@items)
          end

          should "send multiple batches and return nothing" do
            assert(@actual_failures.empty?)
            assert_equal(@expected_requests, @client.requests)
          end
        end

        context "when some records fail" do
          setup do
            @error_respones = [
              [["k1", "v1", "err", "message"], ["k2", "v2", "err", "message"]],
              [["k-next", "v-next", "err", "message"]]
            ]
            @expected_failures = @error_respones.flat_map {|x| x }

            @client = StubClient.new(*@error_respones)
            @producer = TestingProducer.new('stream', @client, {send_size: @send_size})
            @actual_failures = @producer.put_all(@items)
          end

          should "return the failures" do
            assert_equal(@expected_requests, @client.requests)
            assert_equal(@expected_failures, @actual_failures)
          end
        end
      end
    end
  end
end
