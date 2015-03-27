module Telekinesis
  module Consumer
    # A RecordProcessor that uses the given block to process records. Useful to
    # quickly define a consumer.
    #
    # Telekinesis::Consumer::Worker.new(stream: 'my-stream', app: 'tail') do
    #   Telekinesis::Consumer::Block.new do |records, checkpointer|
    #     records.each {|r| puts r}
    #   end
    # end
    class Block < BaseProcessor
      def initialize(&block)
        raise ArgumentError, "No block given" unless block_given?
        @block = block
      end

      def process_records(records, checkpointer)
        @block.call(records, checkpointer)
      end
    end
  end
end
