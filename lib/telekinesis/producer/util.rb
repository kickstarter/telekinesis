java_import java.util.concurrent.locks.ReentrantReadWriteLock

module Telekinesis
  module Util
    # Sugar around java.util.concurrent.ReentrantReadWriteLock so that it's
    # easy to use with blocks.
    #
    # e.g.
    #
    # lock = ReentrantReadWriteLock.new
    # some_value = 12345
    #
    # # In a reader thread
    # lock.read_lock do
    #  # Read some data! This won't block any other calls to read_lock
    # end
    #
    # # In a writer thread
    # lock.write_lock do
    #   # Write some data! This is exclusive with any other call to this lock.
    # end
    class ReadWriteLock
      def initialize(fair = false)
        lock = ReentrantReadWriteLock.new(fair)
        @read = lock.read_lock
        @write = lock.write_lock
      end

      def read_lock
        @read.lock_interruptibly
        yield
      ensure
        @read.unlock
      end

      def write_lock
        @write.lock_interruptibly
        yield
      ensure
        @write.unlock
      end
    end
  end
end
