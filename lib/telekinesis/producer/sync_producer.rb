module Telekinesis
  module Producer
    class SyncProducer
      attr_reader :stream, :client

      def self.create(options = {})
        stream = options[:stream]
        client = Telekinesis::Aws::Client.build(options.fetch(:credentials, {}))
        new(stream, client, options)
      end

      def initialize(stream, client, opts = {})
        @stream = stream or raise ArgumentError, "stream may not be nil"
        @client = client or raise ArgumentError, "client may not be nil"
        @send_size = opts.fetch(:send_size, Telekinesis::Aws::KINESIS_MAX_PUT_RECORDS_SIZE)
      end

      def put(key, data)
        @client.put_record(@stream, key, data)
      end

      def put_all(items)
        items.each_slice(@send_size).each do |batch|
          failures = @client.put_records(@stream, batch)
          on_record_failure(failures) unless failures.empty?
        end
      end

      # Callbacks. These all default to noops.
      #
      # TODO: Do callbacks make sense in a sync implementation?

      def on_record_failure(failures); end
      def on_kinesis_retry(error); end
      def on_kinesis_failure(error); end
    end
  end
end
