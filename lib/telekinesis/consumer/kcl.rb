module Telekinesis
  module Consumer
    java_import com.amazonaws.services.kinesis.clientlibrary.lib.worker.InitialPositionInStream
    java_import com.amazonaws.services.kinesis.clientlibrary.lib.worker.KinesisClientLibConfiguration

    class KCL
      # Create a new consumer that consumes data from a Kinesis stream using the
      # AWS Kinesis Client Library.
      #
      # The KCL uses DynamoDB to register clients as part of the an application
      # and evenly distribute work between all of the clients registered for
      # the same application. See the AWS Docs for more information:
      #
      # http://docs.aws.amazon.com/kinesis/latest/dev/developing-consumer-apps-with-kcl.html
      #
      # KCLs are configured with a hash. The Kinesis `:stream` to consume from
      # is required.
      #
      # KCL clients operate in groups. All consumers with the same `:app` id use
      # DynamoDB to attempt to distribute work evenly among themselves. The
      # `:worker_id` is used to distinguish individual clients (`:worker_id`
      # defaults to the current hostname. If you plan to run more than one KCL
      # client in the same `:app` on the same host, make sure you set this to
      # something unique!).
      #
      # Clients interested in configuring their own AmazonDynamoDB client may
      # pass an instance as the second argument. If not configured, the client
      # will use a default AWS configuration.
      #
      # Any other valid KCL Worker `:options` may be passed as a nested hash.
      #
      # For example, to configure a `tail` app on `some-stream` and use the
      # default `:worker_id`, you might pass the following configuration to your
      # KCL.
      #
      #     config = {
      #       app: 'tail',
      #       stream: 'some-stream',
      #       options: {initial_position_in_stream: 'TRIM_HORIZON'}
      #     }
      #
      # To actually process the stream, a KCL client creates record processors.
      # These are objects that correspond to the KCL's RecordProcessor
      # interface - processors must implement `init`, `process_records`, and
      # `shutdown` methods.
      #
      # http://docs.aws.amazon.com/kinesis/latest/dev/kinesis-record-processor-implementation-app-java.html#kcl-java-interface-v2
      #
      # To specify which record processor to create, pass a block to your
      # distribtued consumer that returns a new record processor. This block
      # may (nay, WILL) be called from a background thread so make sure that
      # it's thread-safe.
      #
      # Telekinesis provides a BaseProcessor that implements no-op versions
      # of all of the required methods to make writing quick processors easier
      # and a Block processor that executes the given block every time
      # `process_records` is called.
      #
      # To write a simple stream tailer, you might use Block as follows:
      #
      #     kcl_worker = Telekinesis::Consumer::KCL.new(config) do
      #       Telekinesis::Consumer::BlockProcessor.new do |records, checkpointer, millis_behind_latest|
      #         records.each{|r| puts r}
      #         $stderr.puts "#{millis_behind_latest} ms behind"
      #         checkpointer.checkpoint
      #       end
      #     end
      #
      #     kcl_worker.run
      #
      def initialize(config, dynamo_client = nil, &block)
        raise ArgumentError, "No block given!" unless block_given?
        kcl_config = self.class.build_config(config)
        @under = com.kickstarter.jruby.Telekinesis.new_worker(kcl_config, config[:executor], dynamo_client, &block)
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
