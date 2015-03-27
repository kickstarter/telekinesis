module Telekinesis
  module Aws
    # A ClientAdapter that wraps the ruby aws-sdk gem (version 2).
    #
    # Since the aws-sdk gem does not appear to be thread-safe, this adapter
    # should not be considered thread safe.
    class RubyClientAdapter < ClientAdapter
      # Build a new client adapter. Credentials are passed directly to the
      # constructor for Aws::Kinesis::Client.
      #
      # See: http://docs.aws.amazon.com/sdkforruby/api/Aws/Kinesis/Client.html
      def self.build(credentials)
        new(Aws::Kinesis::Client.new(credentials))
      end

      def put_record(stream, key, value)
        @client.put_record(stream: stream, partition_key: key, data: value)
      rescue Aws::Errors::ServiceError => e
        raise KinesisError.new(e)
      end

      protected

      def do_put_records(stream, items)
        @client.put_records(build_put_records_request(stream, items)).flat_map do |page|
          page.records
        end
      rescue Aws::Errors::ServiceError => e
        raise KinesisError.new(e)
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
