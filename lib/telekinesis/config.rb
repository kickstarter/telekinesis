java_import com.amazonaws.auth.BasicAWSCredentials
java_import com.amazonaws.internal.StaticCredentialsProvider
java_import com.amazonaws.auth.DefaultAWSCredentialsProviderChain
java_import com.amazonaws.services.kinesis.clientlibrary.lib.worker.InitialPositionInStream
java_import com.amazonaws.services.kinesis.clientlibrary.lib.worker.KinesisClientLibConfiguration

module Telekinesis
  module Config
    class << self
      def producer_config(config_hash = {})
        check_key(config_hash, :stream, "Missing stream")
        is_async = config_hash[:async] || !config_hash.include?(:async)
        [config_hash[:stream], is_async, credentials_provider(config_hash[:creds] || {})]
      end

      # Build a Kinesis consumer configuration from a hash. The following
      # config parameters are required and used to identify the configured
      # client.
      #
      # - app (String): the name of your application.
      # - stream (String): the name of the stream to consume from.
      # - worker_id (String): the name of the worker process using this consumer.
      #
      # The configuration also builds an AWS Credentials Provider. The :creds
      # parameter must be a hash with a :type key. A "basic" provider will use
      # the "access_key_id" and "secret_access_key" parameters to create a
      # `StaticCredentialsProvider`. The "default" provider uses a
      # `DefaultAWSCredentialsProviderChain` to check env variables, system
      # properties, and IAM for credentials.
      #
      # NOTE: The KCL allows you to use separate credentials for Kinesis,
      #       Cloudwatch, and DynamoDB. For now, Telekinesis doesn't support
      #       building a config that complicated from a hash.
      #
      # Any other configuration options on KinesisClientLibConfiguration are
      # passed as a nested `options` hash. Keys in the `options` hash are assumed
      # to correspond to setters (with "with_" prepended) on the config object.
      #
      # An example client configuration:
      #
      # {
      #   app: "this-app",
      #   stream: "a-stream",
      #   creds: { type: "default" }
      #   options: {
      #     max_records: 50
      #     call_process_records_even_for_empty_record_list: false
      #     initial_position_in_stream: "LATEST"
      #   }
      # }
      #
      # Returns a KinesisClientLibConfiguration object.
      def consumer_config(config_hash = {})
        config = KinesisClientLibConfiguration.new(*constructor_args(config_hash))
        config_opts = (config_hash[:options] || {})
        config_opts.each do |k, v|
          setter = "with_#{k}".to_sym
          if config.respond_to?(setter)
            converter = value_converters[k.to_sym]
            if converter
              v = converter.call(v)
            end
            config.send(setter, v)
          end
        end
        config
      end

      def credentials_provider(config_hash)
        case config_hash[:type]
        when "default"
          DefaultAWSCredentialsProviderChain.new
        when "static"
          StaticCredentialsProvider.new(BasicAWSCredentials.new(config_hash[:access_key_id],
                                                                config_hash[:secret_access_key]))
        else
          raise ArgumentError, "Invalid credentials type #{config_hash[:type]}"
        end
      end

      protected

      def constructor_args(config_hash)
        provider = credentials_provider(config_hash[:creds] || {})

        app, stream, worker_id = [:app, :stream, :worker_id].map do |k|
          check_key(config_hash, k, "#{k} is required")
          config_hash[k]
        end

        [app, stream, provider, worker_id]
      end

      def check_key(hash, key, message)
        raise ArgumentError, message unless hash.include?(key)
      end

      def value_converters
        {
          initial_position_in_stream: Proc.new {|x| InitialPositionInStream.value_of(x) }
        }
      end
    end
  end
end
