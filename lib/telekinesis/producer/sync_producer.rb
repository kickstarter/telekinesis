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
      client.put_record(build_request(key, data))
    end

    def put_all(items)
      items.each_slice(MAX_BUFFER_SIZE).each do |batch|
        data = batch.map{|k, v| {partition_key: k, data: v}}
        failures = client.put_records(stream, data).flat_map do |page|
          page.records.reject{|r| r.error_code.nil?}
        end
        on_failure(failures.size, failures) if (failures.size > 0)
      end
    end

    def on_failure(failures)
      Telekinesis.logger.error("put_records returned #{failures.size} failures")
    end
  end
end
