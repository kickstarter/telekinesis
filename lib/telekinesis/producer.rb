require "telekinesis"

module Telekinesis
  module Producer; end
end

require "telekinesis/producer/noop_failure_handler"
require "telekinesis/producer/warn_failure_handler"
require "telekinesis/producer/sync_producer"
require "telekinesis/producer/async_producer" if RUBY_PLATFORM =~ /java/
