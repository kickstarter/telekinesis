module Telekinesis
  module Consumer
    class PlatformWarning
      def initialize(config, &block)
        raise "Kinesis consumers are only available on the JVM"
      end
    end
  end
end

