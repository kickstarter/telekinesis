module Telekinesis
  class Producer
    class << self
      def create(opts = {}, &block)
        if opts.fetch(:async, false)
          build_async_producer(opts, &block)
        else
          build_sync_producer(opts, &block)
        end
      end

      protected

      def build_sync_procucer(opts, &block)
        options = opts.copy
        stream = options.delete(:stream)
        creds_hash = options.delete(:credentials)

        creds = Telekinesis::Config::aws_credentials(creds_hash)
        client = Aws::Kinesis::Client.new(creds)
        with_callbacks(SyncProducer, &block).new(stream, client)
      end

      def build_async_producer(opts, &block)
        raise ArgumentError, "Async producer requires JRuby" unless java?
        java_import com.amazonaws.services.kinesis.AmazonKinesisClient

        options = opts.copy
        stream = options.delete(:stream)
        creds_hash = options.delete(:credentials)

        creds = Telekinesis::Config::credentials_provider(creds_hash)
        client = AmazonKinesisClient.new(creds)
        with_callbacks(AsyncProducer, &block).new(stream, client, options)
      end

      def java?
        RUBY_PLATFORM.match(/java/)
      end

      def with_callbacks(klass, &block)
        if block_given?
          Class.new(klass, &block)
        else
          klass
        end
      end
    end
  end
end
