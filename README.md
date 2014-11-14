## What is this?

Telekinesis is a high-level JRuby client for Amazon Kinesis that wraps the [AWS
Java SDK](http://aws.amazon.com/sdk-for-java/) and the [Kinesis Client
Library](https://github.com/awslabs/amazon-kinesis-client).

## Why?

TKTKTKTK

## Requirements

* Java 1.6 or higher.
* JRuby 1.7.16

If you want to build from source, you need to have Apache Maven installed.

## Credentials

Telekinesis wraps the AWS Java SDK, so credentials are
[`AWSCredentials`](http://docs.aws.amazon.com/AWSJavaSDK/latest/javadoc/com/amazonaws/auth/AWSCredentials.html).
This gives you the flexibility to use [explicit
credentials](https://github.com/Widen/aws-sdk-for-java/blob/master/src/main/java/com/amazonaws/internal/StaticCredentialsProvider.java)
or
[IAM](http://docs.aws.amazon.com/AWSJavaSDK/latest/javadoc/com/amazonaws/auth/AWSCredentialsProvider.html)
at your discretion.

## How does it all work?

### Producers

Telekinesis includes a high-level
[Producer](http://docs.aws.amazon.com/kinesis/latest/dev/amazon-kinesis-producers.html)
that sends data to Kinesis in batches. Batching increases throughput to Kinesis
at the expense of latency by cutting down the number of API requests the client
has to make to AWS.

The default Producer batches records in the background before sending data to
Kinesis. A synchronous single-threaded client is also available if you're
interested in managing your own threading model.

The following example creates a Producer with the default batch serializer (see
below), sends every line in `ARGF` to Kinesis, and then shuts down cleanly.

```ruby
producer = Telekinesis.producer(stream: "an-stream", creds: {type: "default"})

ARGF.each_line do |line|
  producer.put(line.chomp)
end

# Blocking shutdown (see below for details)
producer.shutdown(true, 5)
```

Producers have three methods:

- The **`put(data)`** method sends the given data to Kinesis. Data is
  serialized with the given serializer. Returns `true` if the producer accepted
  the data, and `false` otherwise. Data may be an instance of any kind of data
  that the configured serializer can handle.

- The **`flush`** method forces any data buffered in the producer to be sent to
  Kinesis immediately.

- The **`shutdown(block = false, duration = nil, unit = nil)`** method stops
  the producer from accepting any more data, sends any queued data to Kinesis,
  and stops any background tasks it may be managing. Shutdown can optionally
  block for a given period of time, in which case it returns the same value as
  `await`.

- The **`await(duration = 10, unit = TimeUnit::SECONDS)`** method waits for the
  producer to shut down cleanly. Returns `false` if the worker timed out
  without shutting down cleanly and `true` otherwise. `duration` must be an
  integer and `unit` must be a `TimeUnit` value from `java.util.concurrent`. By
  default, `unit` is `SECONDS`.

### Batch Serializers

Batch serializers are designed to create batches of data that are as [large as
possible](http://docs.aws.amazon.com/kinesis/latest/dev/service-sizes-and-limits.html)
before sending them to Kinesis. The current maximum batch size is 50 KB. Batch
serializers are designed to *never* overshoot that limit.

Batch serializers are built around the `BatchSerializer` interface.

```ruby
class BatchSerializer
  def write(record)
    raise NotImplementedError
  end

  def flush
    raise NotImplementedError
  end

  def read(bytes)
    raise NotImplementedError
  end
end
```

A serializer may accept any kind of data in the `write` method, but must return
a `byte[]` (a Java array of `byte`) from both the `write` and `flush` methods.

When the `write` method is called, the serializer is responsible for
determining if the next batch of records is ready. The `write` method may
return `nil` if there is no data available, or may return a `byte[]`.

Batch serializers also implement a `read` method that takes a serialized
`byte[]` payload and returns the data that was serialized into that batch.

Two serializers are provided by the library:

- The `GZIPStringSerializer` serializer accepts Strings and serializes them as
  a sequence of GZIP compressed `length, byte[]` pairs. The `length` element is
  a 4-byte big-endian int, and strings are converted to bytes (via their
  current encoding) using JRuby's `to_java_bytes` method.

- The `DelimitedStringSerializer` serializer accepts Strings and serializes
  them using JRuby's `to_java_bytes` method. Strings have a specified delimiter
  appended.

### Async Producer

The Async Producer is used by default. Accepted data is queued for processing,
and handled by one of a number of background threads that each individually
batch data and send it to Kinesis. The optimal number of workers to configure
an Async Producer with depends entirely on your serializer, data rate, and
latency requirements. We highly suggest testing.

Configuring an Async Producer with a custom serializer is straightforward:

```ruby
producer = Telekinesis.producer(stream: "an-stream", creds: DefaultAWSCredentialsProviderChain.new) do
  MyCustomSerializer.new(my_config_args)
end
```

NOTE: Each background thread will obtain a batch serializer by calling the
passed block. If your serializer is not thread safe (the included serializers
are NOT thread safe!), each call to the block **must** return a new instance.

TODO: More details on Async Producer configuration.

### Sync Producer

You can use a Sync Producer by passing `async: false` in the arguments to
`Telekinesis.producer`. Sync Producers immediately pass data to their serializers
as soon as the `put` method is called, and send data to the Kinesis API as soon
as the serializer makes the next batch of data available.

Sync Producers are **not** thread safe. If you're using a Sync Producer, you
are responsible for managing your own threading model.

## Consumers

Telekinesis provides a wrapper around the [Kinesis Client Library
(KCL)](http://docs.aws.amazon.com/kinesis/latest/dev/kinesis-record-processor-app.html#kinesis-record-processor-overview-kcl).
The KCL handles reading from multiple shards in parallel, deals with split and
merged shards, and checkpoints client positions to a DynamoDB table.

The following example prints the sequence numbers from a Kinesis stream to
`stdout`.

```ruby
my_queue = java.util.concurrent.ArrayBlockingQueue.new(1024)

worker = Kinesis.process_records(build_config) do |records, checkpointer|
  records.each { |r| @queue.put(r) }
  checkpointer.checkpoint
end

Thread.new do
  loop do
    puts my_queue.take.sequence_number
  end
end

# NOTE: worker.run blocks
worker.run
```

*NOTE:* The block passed to `process_records` is being passed to and called from
multiple threads by the Kinesis client. Be careful about what you do in that
block! Things like appending to a regular Array with `<<` or incrementing an
integer outside of the block aren't safe!

Under the hood, `process_records` creates a record processor that uses the
passed block as the `processRecords` method and passes it to a new KCL
[Worker](https://github.com/awslabs/amazon-kinesis-client/blob/master/src/main/java/com/amazonaws/services/kinesis/clientlibrary/lib/worker/Worker.java). The worker manages concurrency and creates a record processor dedicated to each
shard in the stream.

To have more control over the processing each shard, define a class with the
following methods.

```ruby
class MyWorker
  def init(shard_id)
    # Called by the KCL worker on startup with the shard that this worker will
    # be processing records from.
  end

  def process_records(records, checkpointer)
    # Process a batch of records. Checkpoint the app's current position
    # in the stream (or don't!) by calling checkpointer.checkpoint
  end

  def shutdown(checkpointer, reason)
    # Called by the KCL Worker on shutdown.
  end
end
```

This implements a `RecordProcessor` interface defined by the KCL. The `Worker`
class will instantiate a new processor for each shard it needs to handle, and
use the processor to handle records from that shard in a background thread.

*NOTE*: Unfortunately, the [`IRecordProcessor`
interface](https://github.com/awslabs/amazon-kinesis-client/blob/master/src/main/java/com/amazonaws/services/kinesis/clientlibrary/interfaces/IRecordProcessor.java)
includes an `initialize` method that conflicts with the special Ruby
`initialize` method.  Fortunately, Kinesis (the library) includes a shim that
renames the `intialize` method to `init`.

Once you've defined your record processor, create a worker by passing a block
to the `consumer` method that returns a record processor each time it's called.

```ruby
class MyWorker
  def initialize(q)
    @queue = q
  end

  def init(shard_id)
    @shard_id = shard_id
  end

  def process_records(records, checkpointer)
    records.each { |r| @queue.put([@shard_id, r]) }
    checkpointer.checkpoint
  end

  def shutdown(checkpointer, reason)
    # Ignored!
  end
end

my_queue = java.util.concurrent.ArrayBlockingQueue.new(1024)

worker = Kineis.consumer(stream: "a-stream", ...) do
  MyWorker.new(my_queue)
end

Thread.new do
  loop do
    shard, record = my_queue.take
    puts "#{shard}\t#{record.sequence_number}"
  end
end

worker.run
```

TODO: Configuring a Worker.

# Building

Before building you need Java, Maven and JRuby installed.

Install Java through the [Oracle website](http://www.oracle.com/technetwork/java/javase/downloads/index.html).

To install the proper version of JRuby, use `rbenv install`.

Maven is available through Homebrew, via `brew install maven`. It's also
available at [`maven.apache.org`](http://maven.apache.org/).

`rake build:ext` builds the Java shim and packages all of the required Java
classes into a single jar. Since bytecode is portable, the JAR is shipped with
the built gem.

`rake build:gem` builds the complete gem, uberjar and all.

# Installing

`gem install telekinesis-*.gem`

# Testing

Telekinesis comes with a small set of unit tests. Run those with plain ol'
`rake test`.

**NOTE:** The java extension *must* be built and installed before you can run
unit tests.

Integration tests coming soon.

