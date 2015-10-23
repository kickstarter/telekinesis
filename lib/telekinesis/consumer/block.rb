module Telekinesis
  module Consumer
    # A RecordProcessor that uses the given block to process records. Useful to
    # quickly define a consumer.
    #
    # Telekinesis::Consumer::Worker.new(stream: 'my-stream', app: 'tail') do
    #   Telekinesis::Consumer::Block.new do |records, checkpointer, millis_behind_latest|
    #     records.each {|r| puts r}
    #     $stderr.puts "#{millis_behind_latest} ms behind"
    #     checkpointer.checkpoint
    #   end
    # end
    class Block < BaseProcessor
      def initialize(&block)
        raise ArgumentError, "No block given" unless block_given?
        @block = block
      end

      def process_records(input)
        @block.call(input.records, input.checkpointer, input.millis_behind_latest)
      end
    end
  end
end
