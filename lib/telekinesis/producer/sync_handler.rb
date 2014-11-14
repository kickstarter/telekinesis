module Telekinesis
  class SyncHandler
    attr_reader :stream, :client, :serializer

    def initialize(stream, client, serializer)
      @stream = stream
      @client = client
      @serializer = serializer
      @shutdown = false
    end

    def handle(record)
      return false if shutdown

      result = serializer.write(record)
      put_data(result) if result
      true
    end

    def flush
      result = serializer.flush
      put_data(result) if result
    end

    def shutdown(block = false, duration = 2, unit = TimeUnit::SECONDS)
      # Options are ignored
      @shutdown = true
    end

    def await(duration = 10, unit = TimeUnit::SECONDS)
      # Options are ignored
      true
    end

    protected

    def put_data(data)
      Producer.put_data(@client, stream, data)
    end
  end
end
