module Telekinesis; end

unless RUBY_PLATFORM.match(/java/)
  raise "Sorry! Telekinesis is only supported on JRuby"
end

require 'lock_jar'
LockJar.load(resolve: true) # load jar dependencies from Jarfile.lock

require "telekinesis/version"
require "telekinesis/java_util"
require "telekinesis/logging/java_logging"
require "telekinesis/aws"

require "telekinesis/producer"
require "telekinesis/consumer"
