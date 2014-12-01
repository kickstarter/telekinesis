require_relative 'test_helper'

require "telekinesis/stats"

class StatsTest < Minitest::Test
  def assert_logs(expected, method, *args)
      out, _ = capture_subprocess_io do
        Telekinesis.stats.send(method, *args)
      end
      assert_equal(expected, out)
  end

  context "stats logger" do
    setup do
      @old_logger = Telekinesis.logger
      Telekinesis.logger = Logger.new(STDOUT).tap do |l|
        l.level = Logger::DEBUG
        l.formatter = Proc.new do |severity, datetime, progname, message|
          message
        end
      end

      @old_stats = Telekinesis.stats
      Telekinesis.stats = Telekinesis::StatLogger.new("unit_test")
    end

    should("log to stdout on increment"){ assert_logs("unit_test.inc || 1", :increment, "inc") }
    should("log to stdout on decrement"){ assert_logs("unit_test.dec || -1", :decrement, "dec") }
    should("log to stdout on count"){ assert_logs("unit_test.count || 5", :count, "count", 5) }
    should("log to stdout on gauge"){ assert_logs("unit_test.gauge || 123", :gauge, "gauge", 123) }
    should("log to stdout on timing"){ assert_logs("unit_test.timing || 1001ms", :timing, "timing", 1001) }

    teardown do
      Telekinesis.logger = @old_logger
      Telekinesis.stats = @old_stats
    end
  end
end
