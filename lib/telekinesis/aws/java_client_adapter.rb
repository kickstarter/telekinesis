module Telekinesis
  module Aws
    java_import com.amazonaws.services.kinesis.AmazonKinesisClient
    java_import com.amazonaws.services.kinesis.model.PutRecordRequest
    java_import com.amazonaws.services.kinesis.model.PutRecordsRequest
    java_import com.amazonaws.services.kinesis.model.PutRecordsRequestEntry

    class JavaClientAdapter < ClientAdapter
      def self.build(credentials)
        provider = if credentials.empty?
          DefaultAWSCredentialsProviderChain.new
        else
          StaticCredentialsProvider.new(
            BasicAWSCredentials.new(
              credentials[:access_key_id],
              credentials[:secret_access_key]
            )
          )
        end
        client = AmazonKinesisClient.new(provider)
        new(client)
      end

      def put_record(stream, key, value)
        r = PutRecordRequest.new.tap do |request|
          request.stream_name = @stream
          request.partition_key = key
          request.data = value
        end
        @client.put_record(r)
      end

      protected

      def do_put_records(stream, items)
        @client.put_records(build_put_records_request(stream, items))
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
