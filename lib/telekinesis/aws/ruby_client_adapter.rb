module Telekinesis
  module Aws
    class RubyClientAdapter < ClientAdapter
      def self.build(stream, credentials)
        new(stream, Aws::Kinesis::Client.new(credentials))
      end

      def put_record(key, value)
        @client.put_record(stream: @stream, partition_key: key, data: value)
      end

      protected

      def do_put_records(items)
        put_records(build_put_records_request(items)).flat_map do |page|
          page.records
        end
      end

      def build_put_records_request(items)
        {
          stream: @stream,
          records: items.map{|k, v| {partition_key: k, data: v}}
        }
      end
    end
  end
end
