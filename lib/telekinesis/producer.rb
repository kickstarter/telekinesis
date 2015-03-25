module Telekinesis
  module Producer; end
end

require "telekinesis/producer/sync_producer"
require "telekinesis/producer/async_producer" if RUBY_PLATFORM =~ /java/
