require "telekinesis"

module Telekinesis
  module Consumer; end
end

module Telekinesis
  module Consumer
    Worker = if java?
      require "telekinesis/consumer/kcl_worker"
      KclWorker
    else
      require "telekinesis/consumer/platform_warning"
      PlatformWarning
    end
  end
end

