module Telekinesis
  module Aws
    class RubyClientAdapter < ClientAdapter
      def self.build(stream, credentials)
        new(Aws::Kinesis::Client.new(credentials))
      end

      def put_record(stream, key, value)
        @client.put_record(stream: stream, partition_key: key, data: value)
      end

      protected

      def do_put_records(stream, items)
        put_records(build_put_records_request(stream, items)).flat_map do |page|
          page.records
        end
      end

      def build_put_records_request(stream, items)
        {
          stream: stream,
          records: items.map{|k, v| {partition_key: k, data: v}}
        }
      end
    end
  end
end
