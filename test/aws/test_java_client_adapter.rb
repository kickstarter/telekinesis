require_relative '../test_helper'

class JavaClientAdapterTest < Minitest::Test
  java_import com.amazonaws.services.kinesis.model.PutRecordRequest
  java_import com.amazonaws.services.kinesis.model.PutRecordsRequest

  SomeStruct = Struct.new(:field)
  StubResponse = Struct.new(:records)

  class EchoClient
    def put_record(*args)
      args
    end

    def put_records(*args)
      StubResponse.new(args)
    end
  end

  context "JavaClientAdapter" do
    setup do
      @client = Telekinesis::Aws::JavaClientAdapter.new(EchoClient.new)
    end

    context "#put_record" do
      setup do
        # No exceptions, coerced to string. [args, expected]
        @data = [
          [['stream', 'key', 'value'], ['stream', 'key', 'value']],
          [['stream', 123, 123], ['stream', '123', '123']],
          [['stream', SomeStruct.new('key'), SomeStruct.new('value')], ['stream', '#<struct JavaClientAdapterTest::SomeStruct field="key">', '#<struct JavaClientAdapterTest::SomeStruct field="value">']],
        ]
      end

      should "generate aws.PutRecordsRequest" do
        @data.each do |args, expected|
          request, = @client.put_record(*args)
          expected_stream, expected_key, expected_value = expected

          assert_equal(expected_stream, request.stream_name)
          assert_equal(expected_key, request.partition_key)
          assert_equal(expected_value, String.from_java_bytes(request.data.array))
        end
      end
    end

    context "#do_put_records" do
      setup do
        # No exceptions, coerced to string. [args, expected]
        @data = [
          [
            ['stream', [['key', 'value'], [123, 123], [SomeStruct.new('key'), SomeStruct.new('value')]]],
            ['stream', [['key', 'value'], ['123', '123'], ['#<struct JavaClientAdapterTest::SomeStruct field="key">', '#<struct JavaClientAdapterTest::SomeStruct field="value">']]]
          ],
        ]
      end

      should "generate aws.PutRecordsRequest" do
        @data.each do |args, expected|
          request, = @client.send(:do_put_records, *args)
          expected_stream, expected_items = expected

          assert_equal(expected_stream, request.stream_name)
          expected_items.zip(request.records) do |(expected_key, expected_value), record|
            assert_equal(expected_key, record.partition_key)
            assert_equal(expected_value, String.from_java_bytes(record.data.array))
          end
        end
      end
    end
  end
end
