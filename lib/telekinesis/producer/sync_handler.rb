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
      Producer.put_data(@client, stream, data)
    end
  end
end
