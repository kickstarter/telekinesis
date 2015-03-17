require "minitest/autorun"
require "bundler/setup"

Bundler.require(:development)

require "telekinesis/stats"
require "telekinesis/logging"
require "telekinesis/telekinesis-#{Telekinesis::VERSION}.jar"

