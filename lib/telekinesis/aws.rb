require "telekinesis/aws/client_adapter.rb"
require "telekinesis/aws/java_client_adapter"

module Telekinesis
  module Aws
    KINESIS_MAX_PUT_RECORDS_SIZE = 500
    Client = JavaClientAdapter
  end
end
