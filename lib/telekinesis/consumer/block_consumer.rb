module Telekinesis
  class BlockRecordProcessor
    def initialize(&block)
      raise ArgumentError, "No block given" unless block_given?
      @block = block
    end

    def init(shard_id)
      # Ignored
    end

    def process_records(records, checkpointer)
      @block.call(records, checkpointer)
    end

    def shutdown(checkpointer, reason)
      # Ignored
    end
  end
end
