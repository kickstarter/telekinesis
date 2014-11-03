module Telekinesis; end

unless RUBY_PLATFORM.match(/java/)
  raise "Sorry! Telekinesis is only supported on JRuby"
end

require "telekinesis/version"
require "telekinesis/telekinesis-#{Telekinesis::VERSION}.jar"
require "telekinesis/java_util"
require "telekinesis/logging/java_logging"
require "telekinesis/aws"

require "telekinesis/producer"
require "telekinesis/consumer"
