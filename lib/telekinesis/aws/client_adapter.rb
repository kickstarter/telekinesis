module Telekinesis
  module Aws
    # Base class for other ClientAdapters. Client adapters exist to make
    # switching between platforms easy and painless.
    #
    # The base adapter defines the interface and provides convience methods.
    class ClientAdapter
      # Build a new client given AWS credentials.
      #
      # Credentials must be supplied as a hash that contains symbolized
      # :access_key_id and :secret_access_key keys.
      def self.build(credentials)
        raise NotImplementedError
      end

      def initialize(client)
        @client = client
      end

      # Make a put_record call to the underlying client. Must return an object
      # that responds to `shard_id` and `sequence_number`.
      def put_record(stream, key, value)
        raise NotImplementedError
      end

      # Make a put_records call to the underlying client. If the request
      # succeeds but returns errors for some records, the original [key, value]
      # pair is zipped with the [error_code, error_message] pair and the
      # offending records are returned.
      def put_records(stream, items)
        response = do_put_records(stream, items)
        failures = items.zip(response).reject{|_, r| r.error_code.nil?}

        failures.map do |(k, v), r|
          [k, v, r.error_code, r.error_message]
        end
      end

      protected

      # Put an enumerable of [key, value] pairs to the given stream. Returns an
      # enumerable of response objects the same size as the given list of items.
      #
      # Response objects must respond to `error_code` and `error_message`. Any
      # response with a nil error_code is considered successful.
      def do_put_records(stream, items)
        raise NotImplementedError
      end
    end
  end
end

