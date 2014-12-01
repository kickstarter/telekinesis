require "telekinesis/stats/stat_logger"

module Telekinesis
  @stats = StatLogger.new("telekinesis")

  class << self
    attr_accessor :stats
  end
end
