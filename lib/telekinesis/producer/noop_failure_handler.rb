module Telekinesis
  module Producer
    class NoopFailureHandler
      def on_record_failure(item_error_tuples); end
      def on_kinesis_retry(error, items); end
      def on_kinesis_failure(error, items); end
    end
  end
end
