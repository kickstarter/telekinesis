module Telekinesis
  class SyncProducer
    # FIXME: Move this into KinesisUtils or something. Used in two places.
    MAX_BUFFER_SIZE = 500

    attr_reader :stream, :client

    def initialize(stream, client)
      @stream = stream
      @client = client
    end

    def put(key, data)
      client.put_record(stream: stream, data: data, partition_key: key)
    end

    def put_all(items)
      items.each_slice(MAX_BUFFER_SIZE).each do |batch|
        failures = put_records(batch).flat_map do |page|
          page.records.reject{|r| r.error_code.nil?}
        end
        on_failure(failures.size, failures) if (failures.size > 0)
      end
    end

    def on_failure(failures)
      Telekinesis.logger.error("put_records returned #{failures.size} failures")
    end

    protected

    def put_records(items)
      client.put_records(
        stream: stream,
        records: items.map{|k, v| {partition_key: k, data: v}}
      )
    end
  end
end
