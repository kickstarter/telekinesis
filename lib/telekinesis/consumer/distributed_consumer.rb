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
      # DistributedConsumers are configured with a hash. The Kinesis `:stream`
      # to consume from is required.
      #
      # DistribtuedConsumers operate in groups. All consumers with the same
      # `:app` id use dynamo to attempt to distribute work evenly among
      # themselves. The `:worker_id` is used to distinguish individual clients
      # (`:worker_id` defaults to the current hostname. If you plan to run more
      # than one DistributedConsumer in the same `:app` per host, make sure you
      # set this to something unique!).
      #
      # Any other valid KCL Worker `:options` may be passed as a hash.
      #
      # For example, to configure a `tail` app on `some-stream` and use the
      # default `:worker_id`, you might pass the following configuration to your
      # DistributedConsumer.
      #
      #     config = {
      #       app: 'tail',
      #       stream: 'some-stream',
      #       options: {initial_position_in_stream: 'TRIM_HORIZON'}
      #     }
      #
      # To actually process the stream, a DistribtuedConsumer creates
      # record processors. These are objects that correspond to the KCL's
      # RecordProcessor interface - processors must implement `init`,
      # `process_records`, and `shutdown` methods.
      #
      # http://docs.aws.amazon.com/kinesis/latest/dev/kinesis-record-processor-implementation-app-java.html#kinesis-record-processor-implementation-interface-java
      #
      # To specify which record processor to create, pass a block to your
      # distribtued consumer that returns a new record processor. This block
      # may (nay, WILL) be called from a background thread so make sure that
      # it's thread-safe.
      #
      # Telekinesis provides a BaseProcessor that implements no-op versions
      # of all of the required methods to make writing quick processors easier
      # and a Block processor that executes the specified block every time
      # `process_records` is called.
      #
      # To write a stream tailer, you might use Block as follows:
      #
      #     Telekinesis::Consumer::DistributedConsumer.new(config) do
      #       Telekinesis::Consumer::Block do |records, _|
      #         records.each {|r| puts r}
      #       end
      #     end
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
          Thread.new { @under.run }
        else
          @under.run
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
            if k.to_s == 'initial_position_in_stream'
              kcl_config.with_initial_position_in_stream(InitialPositionInStream.value_of(v))
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
