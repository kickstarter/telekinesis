module Telekinesis; end

require "telekinesis/version"
require "telekinesis/telekinesis-#{Telekinesis::VERSION}.jar" if RUBY_PLATFORM.match(/java/)
require "telekinesis/aws"
require "telekinesis/producer"


