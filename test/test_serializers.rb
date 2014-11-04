require_relative 'test_helper'


java_import java.io.ByteArrayInputStream
java_import java.util.zip.GZIPInputStream

class SerializersTest < Minitest::Test
  context "DelimitedSerializer" do
    should "return nil when flushed while empty" do
      assert_nil(Telekinesis::DelimitedSerializer.new(100, "\n").flush)
    end

    should "flush when told to" do
      serializer = Telekinesis::DelimitedSerializer.new(100, "\n")
      5.times do
        assert_nil serializer.write("banana")
      end

      assert_equal("banana\n" * 5, String.from_java_bytes(serializer.flush))
    end

    should "flush when enough data is written" do
      serializer = Telekinesis::DelimitedSerializer.new(100, "\n")

      14.times do
        # 'banana\n' is 7 chars, 7 * 14 = 98
        assert_nil serializer.write("banana")
      end
      assert_equal("banana\n" * 14,
                   String.from_java_bytes(serializer.write("banana")))
      assert_equal("banana\n",
                   String.from_java_bytes(serializer.flush))
    end

    should "read what it writes" do
      data = ["banana"] * 10
      serializer = Telekinesis::DelimitedSerializer.new(100, "\n")

      data.each do |d|
        serializer.write(d)
      end
      assert_equal(data, serializer.read(serializer.flush))
    end
  end

  context "GZIPDelimitedSerializer" do
    should "return nil when flushed while empty" do
      assert_nil(Telekinesis::GZIPDelimitedSerializer.new(100, "\n").flush)
    end

    should "flush all written data" do
      serializer = Telekinesis::GZIPDelimitedSerializer.new(100, "\n")
      5.times do
        assert_nil serializer.write("banana")
      end
      assert_equal("banana\n" * 5,
                   GZIPInputStream.new(ByteArrayInputStream.new(serializer.flush)).to_io.read)
    end

    should "flush when enough data is written" do
      serializer = Telekinesis::GZIPDelimitedSerializer.new(100, "\n")

      9.times do
        assert_nil serializer.write("banana")
      end
      res = serializer.write("banana")

      assert_equal(97, res.size)
      assert_equal("banana\n" * 9,
                   GZIPInputStream.new(ByteArrayInputStream.new(res)).to_io.read)
    end

    should "write valid GZIP data" do
      data = ["here is a sentence I would like to compress"] * 2
      serializer = Telekinesis::GZIPDelimitedSerializer.new(1024, "\n")
      data.each do |d|
        serializer.write(d)
      end
      assert_equal(data, serializer.read(serializer.flush))
    end
  end
end
