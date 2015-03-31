module Telekinesis
  module Aws
    java_import com.amazonaws.AmazonClientException
    java_import com.amazonaws.auth.DefaultAWSCredentialsProviderChain
    java_import com.amazonaws.services.kinesis.AmazonKinesisClient
    java_import com.amazonaws.services.kinesis.model.PutRecordRequest
    java_import com.amazonaws.services.kinesis.model.PutRecordsRequest
    java_import com.amazonaws.services.kinesis.model.PutRecordsRequestEntry

    # A ClientAdapter that wraps the AWS Java SDK.
    #
    # Since the underlying Java client is thread safe, this adapter is thread
    # safe.
    class JavaClientAdapter < ClientAdapter
      # Build a new client adapter. `credentials` is a hash keyed with
      # `:access_key_id` and `:secret_access_key`. If this hash is left blank
      # (the default) the client uses the DefaultAWSCredentialsProviderChain to
      # look for credentials.
      def self.build(credentials = {})
        client = AmazonKinesisClient.new(build_credentials_provider(credentials))
        new(client)
      end

      def self.build_credentials_provider(credentials)
        if credentials.empty?
          DefaultAWSCredentialsProviderChain.new
        else
          StaticCredentialsProvider.new(
            BasicAWSCredentials.new(
              credentials[:access_key_id],
              credentials[:secret_access_key]
            )
          )
        end
      end

      def put_record(stream, key, value)
        r = PutRecordRequest.new.tap do |request|
          request.stream_name = @stream
          request.partition_key = key
          request.data = value
        end
        @client.put_record(r)
      rescue AmazonClientException => e
        raise KinesisError.new(e)
      end

      protected

      def do_put_records(stream, items)
        result = @client.put_records(build_put_records_request(stream, items))
        result.records
      rescue AmazonClientException => e
        raise KinesisError.new(e)
      end

      def build_put_records_request(stream, items)
        entries = items.map do |key, data|
          PutRecordsRequestEntry.new.tap do |entry|
            entry.partition_key = key
            entry.data = ByteBuffer.wrap(data.to_java_bytes)
          end
        end
        PutRecordsRequest.new.tap do |request|
          request.stream_name = stream
          request.records = entries
        end
      end
    end
  end
end
