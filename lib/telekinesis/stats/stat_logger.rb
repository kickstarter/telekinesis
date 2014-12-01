require "telekinesis/logging"

module Telekinesis
  class StatLogger
    def initialize(namespace = nil)
      @namespace = namespace
    end

    def increment(stat, sample_rate = 1)
      log_if_debug("%s || 1", stat)
    end

    def decrement(stat, sample_rate = 1)
      log_if_debug("%s || -1", stat)
    end

    def count(stat, count, sample_rate = 1)
      log_if_debug("%s || %s", stat, count)
    end

    def gauge(stat, value)
      log_if_debug("%s || %s", stat, value)
    end

    def timing(stat, ms, sample_rate = 1)
      log_if_debug("%s || %sms", stat, ms)
    end

    def time(stat, sample_rate = 1)
      start = current_time_millis
      result = yield
      timing(stat, current_time_millis - start, sample_rate)
      result
    end

    protected

    def current_time_millis
      (Time.now.to_f * 1000).to_i
    end

    def log_if_debug(fmt, *args)
      logger = Telekinesis.logger
      if logger.debug?
        logger.debug("#{@namespace ? @namespace + '.' : ''}#{fmt % args}")
      end
    end
  end
end
