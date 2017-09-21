module Telekinesis
  module Producer
    # A synchronous Kinesis producer.
    #
    # This class is thread safe if and only if the underlying
    # Telekines::Aws::Client is threadsafe. In practice, this means this client
    # is threadsafe on JRuby and not thread safe elsewhere.
    class SyncProducer
      attr_reader :stream, :client

      # Create a new Producer.
      #
      # AWS credentials may be specified by using the `:credentials` option and
      # passing a hash containing your `:access_key_id` and `:secret_access_key`.
      # If unspecified, credentials will be fetched from the environment, an
      # ~/.aws/credentials file, or the current instance metadata.
      #
      # `:send_size` may also be used to configure the maximum batch size used
      # in `put_all`. See `put_all` for more info.
      def self.create(options = {})
        stream = options[:stream]
        client = Telekinesis::Aws::Client.build(
          options.fetch(:credentials, {}),
          options[:endpoint]
        )
        new(stream, client, options)
      end

      def initialize(stream, client, opts = {})
        @stream = stream or raise ArgumentError, "stream may not be nil"
        @client = client or raise ArgumentError, "client may not be nil"
        @send_size = opts.fetch(:send_size, Telekinesis::Aws::KINESIS_MAX_PUT_RECORDS_SIZE)
      end

      # Put an individual k, v pair to Kinesis immediately. Both k and v must
      # be strings.
      #
      # Returns once the call to Kinesis is complete.
      def put(key, data)
        @client.put_record(@stream, key, data)
      end

      # Put all of the [k, v] pairs to Kinesis in as few requests as possible.
      # All of the ks and vs must be strings.
      #
      # Each request sends at most `:send_size` records. By default this is the
      # Kinesis API limit of 500 records.
      def put_all(items)
        items.each_slice(@send_size).flat_map do |batch|
          @client.put_records(@stream, batch)
        end
      end
    end
  end
end
