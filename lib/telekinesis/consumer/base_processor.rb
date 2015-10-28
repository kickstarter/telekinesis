module Telekinesis
  module Consumer
    # A RecordProcessor with no-op implementations of all of the required
    # IRecordProcessor methods. Override it to implement simple IRecordProcessors
    # that don't need to do anything special on init or shutdown.
    class BaseProcessor
      def init(initialization_input); end
      def process_records(process_records_input); end
      def shutdown(shutdown_input); end
    end
  end
end
