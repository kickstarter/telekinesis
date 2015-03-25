module Telekinesis
  module Aws
    class ClientAdapter
      def self.build(stream, client)
        raise NotImplementedError
      end

      def initialize(stream, client)
        @stream = stream
        @client = client
      end

      def put_record(key, value)
        raise NotImplementedError
      end

      def put_records(items)
        response = do_put_records(items)
        failures = items.zip(response).reject{|_, r| r.error_code.nil?}

        failures.map do |(k, v), r|
          [k, v, r.error_code, error_message]
        end
      end
    end
  end
end
