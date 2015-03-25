module Telekinesis
  module Aws
    KINESIS_MAX_PUT_RECORDS_SIZE = 500
  end
end
require "telekinesis/aws/client_adapter.rb"

module Telekinesis
  module Aws
    Client = if RUBY_PLATFORM.match(/java/)
      require "telekinesis/aws/java_client_adapter"
      JavaClientAdapter
    else
      require "telekinesis/aws/ruby_client_adapter"
      RubyClientAdapter
    end
  end
end

