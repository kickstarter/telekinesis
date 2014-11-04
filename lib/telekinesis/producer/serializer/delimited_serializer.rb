java_import java.io.ByteArrayOutputStream

module Telekinesis
  class DelimitedSerializer
    attr_reader :target_size, :delim, :delim_bytes, :delim_size

    def initialize(target_size, delim)
      @target_size = target_size
      @delim = delim
      @delim_bytes = delim.to_java_bytes
    end

    def write(record)
      ret = flush if next_size(record) > target_size
      output_stream.write(record.to_java_bytes)
      output_stream.write(delim_bytes)
      ret
    end

    def flush
      return nil if output_stream.size == 0

      bytes = output_stream.to_byte_array
      output_stream.reset
      bytes
    end

    def read(bytes)
      String.from_java_bytes(bytes).split(delim)
    end

    protected

    def next_size(next_record)
      output_stream.size + next_record.bytesize + delim_bytes.size
    end

    def output_stream
      @output_stream ||= ByteArrayOutputStream.new(target_size)
    end
  end
end

