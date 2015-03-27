module Telekinesis
  module JavaUtil
    java_import java.util.concurrent.locks.ReentrantReadWriteLock

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
    #  # Read some data! This won't block any other calls to read_lock, but will
    #  # block if another thread is in a section guarded by write_lock.
    # end
    #
    # # In a writer thread
    # lock.write_lock do
    #   # Write some data! This is exclusive with *any* other code guarded by
    #   # either read_lock or write_lock.
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
