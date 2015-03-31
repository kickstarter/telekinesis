require "telekinesis"
require "telekinesis/consumer/base_processor"
require "telekinesis/consumer/block"

module Telekinesis
  module Consumer
    if java?
      require "telekinesis/consumer/distributed_consumer"
    else
      warn "There are no consumers available on your platform!"
    end
  end
end

