module Telekinesis
  module Producer
    # A simple FailureHandler that logs errors with `warn`. Available as an
    # example and an easy default.
    class WarnFailureHandler
      def on_record_failure(item_err_pairs)
        warn "Puts for #{item_err_pairs.size} records failed!"
      end

      # Do nothing on retry. Let it figure itself out.
      def on_kinesis_retry(err, items); end

      def on_kinesis_failure(err, items)
        warn "PutRecords request with #{items.size} items failed!"
        warn format_bt(err)
      end

      protected

      def format_bt(e)
        e.backtrace ? e.backtrace.map{|l| "!  #{l}"}.join("\n") : ""
      end
    end
  end
end
