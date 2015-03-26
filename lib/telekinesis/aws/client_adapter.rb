module Telekinesis
  module Aws
    class ClientAdapter
      def self.build(credentials)
        raise NotImplementedError
      end

      def initialize(client)
        @client = client
      end

      def put_record(key, value)
        raise NotImplementedError
      end

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

