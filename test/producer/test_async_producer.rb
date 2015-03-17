require_relative '../test_helper'

require "telekinesis/producer/async_producer"


class AsyncProducerTest < Minitest::Test
  context "async producer" do
    context "when shutdown is called" do
      should "shutdown all workers" do
        assert false
      end

      should "not accept events while shut down" do
        assert false
      end

      context "while put is being called" do
        should "wait for the put to return" do
          assert false
        end
      end
    end
  end
end
