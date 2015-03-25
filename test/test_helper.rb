require "minitest/autorun"
require "bundler/setup"
Bundler.require(:development)

require "telekinesis"

# NOTE: only valid in Java tests. Can get defined anywhere.
def string_from_bytebuffer(bb)
  String.from_java_bytes bb.array
end
