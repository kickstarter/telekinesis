module Telekinesis
  class SyncHandler
    attr_reader :stream, :client, :serializer

    def initialize(stream, client, serializer)
      @stream = stream
      @client = client
      @serializer = serializer
    end

    def handle(record)
      result = serializer.write(record)
      put_data(result) if result
    end

    def flush
      result = serializer.flush
      put_data(result) if result
    end

    def drain(*args)
      flush
      []
    end

    protected

    def put_data(data)
      client.put_record(Producer.build_request(stream, data))
    end
  end
end
