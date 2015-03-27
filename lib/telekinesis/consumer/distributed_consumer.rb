module Telekinesis
  module Consumer
    java_import com.amazonaws.services.kinesis.clientlibrary.lib.worker.InitialPositionInStream
    java_import com.amazonaws.services.kinesis.clientlibrary.lib.worker.KinesisClientLibConfiguration

    class DistributedConsumer
      # Create a new consumer that consumes data from a Kinesis stream.
      # DistributedConsumers use DynamoDB to register as part of the same
      # application and evenly distribute work between them. See the
      # AWS Docs for more information:
      #
      # http://docs.aws.amazon.com/kinesis/latest/dev/developing-consumer-apps-with-kcl.html
      #
      # KclWorkers are configured with a hash. The Kinesis `:stream` is required
      # as is the `:app` that the worker is a part of. The `:worker_id` (which
      # is used to distinguish individual clients from one another) may also be
      # explicitly specified - it defaults to the current hostname, so if you
      # plan to run multiple workers on the same host, make sure to explicitly
      # set this.
      #
      # Any other valid KCL Worker `:options` may be passed as a hash.
      #
      # For example, to configure a `tail` app on `some-stream`:
      #
      #     {
      #       stream: 'interesting-data',
      #       app: 'my-tailer',
      #       options: {initial_position_in_stream: 'TRIM_HORIZON'}
      #     }
      #
      def initialize(config, &block)
        raise ArgumentError, "No block given!" unless block_given?
        kcl_config = self.class.build_config(config)
        @under = com.kickstarter.jruby.Telekinesis.new_worker(kcl_config, &block)
      end

      # Return the underlying KCL worker. It's a java.lang.Runnable.
      def as_runnable
        @under
      end

      # Start the KCL worker. If background is set to `true`, the worker is
      # started in its own JRuby Thread and the Thread is returned. Otherwise,
      # starts in the current thread and returns nil.
      def run(background = false)
        if background
          Thread.new { @under.start }
        else
          @under.start
        end
      end

      protected

      def self.build_config(config)
        creds_hash = config.fetch(:credentials, {})
        credentials_provider = Telekinesis::Aws::JavaClientAdapter.build_credentials_provider(creds_hash)

        # App and Stream are mandatory.
        app, stream = [:app, :stream].map do |k|
          raise ArgumentError, "#{k} is required" unless config.include?(k)
          config[k]
        end
        # Use this host as the worker_id by default.
        worker_id = config.fetch(:worker_id, `hostname`.chomp)

        KinesisClientLibConfiguration.new(app, stream, credentials_provider, worker_id).tap do |kcl_config|
          config.fetch(:options, {}).each do |k, v|
            # Handle initial position in stream separately. It's the only option
            # that requires a value conversion.
            if k == :initial_position_in_stream
              pos = InitialPositionInStream.value_of(initial_position)
              kcl_config.with_initial_position_in_stream(pos)
            else
              setter = "with_#{k}".to_sym
              if kcl_config.respond_to?(setter)
                kcl_config.send(setter, v)
              end
            end
          end
        end
      end
    end
  end
end
