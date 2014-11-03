require_relative '../test_helper'

class ClientAdapterTest < Minitest::Test
  StubResponse = Struct.new(:error_code, :error_message)

  class EvenRecordsAreErrors < Telekinesis::Aws::ClientAdapter
    def do_put_records(stream, items)
      items.each_with_index.map do |_, idx|
        err, message = idx.even? ? ["error-#{idx}", "message-#{idx}"] : [nil, nil]
        StubResponse.new(err, message)
      end
    end
  end

  context "ClientAdapter" do
    context "put_records" do
      setup do
        @client = EvenRecordsAreErrors.new(nil)
        @items = 10.times.map{|i| ["key-#{i}", "value-#{i}"]}
        @expected = 10.times.select{|i| i.even?}
                            .map{|i| ["key-#{i}", "value-#{i}", "error-#{i}", "message-#{i}"]}
      end

      should "zip error responses with records" do
        assert(@expected, @client.put_records('stream', @items))
      end
    end
  end
end
