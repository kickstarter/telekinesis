module Telekinesis; end


def java?
  RUBY_PLATFORM.match(/java/)
end

require "telekinesis/version"

if java?
  require "telekinesis/telekinesis-#{Telekinesis::VERSION}.jar"
  require "telekinesis/java_util"
  require "telekinesis/logging/java_logging"
end

require "telekinesis/aws"


