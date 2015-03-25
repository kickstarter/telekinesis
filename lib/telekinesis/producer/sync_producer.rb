module Telekinesis
  module Producer
    class SyncProducer
      attr_reader :stream, :client

      def initialize(stream, client, opts = {})
        @stream = stream
        @client = client
        @max_batch_size = opts.fetch(:max_batch_size, Telekinesis::Aws::KINESIS_MAX_PUT_RECORDS_SIZE)
      end

      def put(key, data)
        client.put_record(stream: stream, data: data, partition_key: key)
      end

      def put_all(items)
        items.each_slice(@max_batch_size).each do |batch|
          failures = put_records(batch).flat_map do |page|
            page.records.reject{|r| r.error_code.nil?}
          end
          on_record_failure(failures.size, failures) if (failures.size > 0)
        end
      end

      # Callbacks. These all default to noops.

      def on_record_failure(failures); end
      # TODO: do I actually want retries here?
      def on_kinesis_retry(error); end
      def on_kinesis_failure(error); end

      protected

      # FIXME: implement retries
      def put_records(items)
        client.put_records(
          stream: stream,
          records: items.map{|k, v| {partition_key: k, data: v}}
        )
      end
    end
  end
end
