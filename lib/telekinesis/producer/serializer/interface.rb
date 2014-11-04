module Telekinesis
  ##
  # A serializer that writes a single blob out binary output for one or
  # more input records. Seralizers must be able to read what they've
  # written.
  #
  # Serialization is expected to be a stateful affair. Records come in one at
  # a time for serialization, and blobs are only produced once the serializer
  # determines that batch size is large enough to make serialization worth the
  # effort.
  #
  # Deserialization is a one-shot affair that converts a serialized batch into
  # an array of records.
  #
  # The split between the two means that serialization may often not be thread
  # safe, while deserialization is.
  class BatchSerializer
    # Write the next record to this serializer.
    #
    # Returns the next serialized blob as a Java `byte` array if the
    # serializer is ready to produce output. Returns nil otherwise.
    def write(record)
      raise NotImplementedError
    end

    # Flushes any data remaining in the serializer and returns a binary
    # blob as a Java `byte` array. This should never return nil, but may
    # return an empty array of `byte`s.
    def flush
      raise NotImplementedError
    end

    # Read a Java `byte` array and return a Ruby list of strings. Reverse
    # the serialization process.
    def read(bytes)
      raise NotImplementedError
    end
  end
end
