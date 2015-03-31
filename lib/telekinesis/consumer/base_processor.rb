module Telekinesis
  module Consumer
    # A RecordProcessor with no-op implementations of all of the required
    # IRecordProcessor methods. Override it to implement simple IRecordProcessors
    # that don't need to do anything special on init or shutdown.
    class BaseProcessor
      def init(shard_id); end
      def process_records(records, checkpointer); end
      def shutdown(checkpointer, reason); end
    end
  end
end
