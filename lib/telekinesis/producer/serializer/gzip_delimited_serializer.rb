java_import java.io.ByteArrayInputStream
java_import java.io.ByteArrayOutputStream
java_import java.util.zip.GZIPInputStream
java_import java.util.zip.GZIPOutputStream

module Telekinesis
  # Serialize records as Gzipped text, delimited by the given string.
  #
  # This class is **not** thread-safe.
  class GZIPDelimitedSerializer
    attr_reader :target_size, :delim, :delim_bytes

    def initialize(target_size, delim)
      @target_size = target_size
      @delim = delim
      @delim_bytes = delim.to_java_bytes
      @records_in_batch = 0
    end

    def write(record)
      ret = flush if next_size(record) > target_size
      gzip_stream.write(record.to_java_bytes)
      gzip_stream.write(delim_bytes)
      gzip_stream.flush
      @records_in_batch += 1
      ret
    end

    def flush
      return nil if @records_in_batch == 0

      gzip_stream.finish
      bytes = byte_stream.to_byte_array
      byte_stream.reset
      @gzip_stream = nil
      @records_in_batch = 0
      bytes
    end

    def read(bytes)
      gz = GZIPInputStream.new(ByteArrayInputStream.new(bytes))
      gz.to_io.read.split(delim)
    end

    protected

    attr_reader :byte_stream, :gzip_stream

    def next_size(next_record)
      # reserve 8 bytes for the GZIP footer. only written at the last record,
      # but its better to overestimate.
      (next_record.bytesize + delim_bytes.size + byte_stream.size) + 8
    end

    def byte_stream
      @byte_stream ||= ByteArrayOutputStream.new(target_size)
    end

    def gzip_stream
      @gzip_stream ||= GZIPOutputStream.new(byte_stream, true)
    end
  end
end
