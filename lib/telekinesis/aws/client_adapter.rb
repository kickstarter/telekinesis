module Telekinesis
  module Aws
    # Base class for other ClientAdapters. Client adapters exist to make
    # switching between platforms easy and painless.
    #
    # The base adapter defines the interface and provides convience methods.
    class ClientAdapter
      def self.build(credentials)
        raise NotImplementedError
      end

      def initialize(client)
        @client = client
      end

      # Make a put_record call to the underlying client. Must return an object
      # that responds to `shard_id` and `sequence_number`.
      def put_record(key, value)
        raise NotImplementedError
      end

      # Make a put_records call to the underlying client. If the request
      # succeeds but returns errors for some records, the original [key, value]
      # pair is zipped with the [error_code, error_message] pair and the
      # offending records are returned.
      #
      # Implementors of do_put_records must return an enumerable of items that
      # respond to error_code and error_message. The enumerable should contain
      # one object for every item in items. Items that were succesfully put
      # shoudl have a nil error code.
      def put_records(stream, items)
        response = do_put_records(stream, items)
        failures = items.zip(response).reject{|_, r| r.error_code.nil?}

        failures.map do |(k, v), r|
          [k, v, r.error_code, r.error_message]
        end
      end
    end
  end
end

