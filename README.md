# Telekinesis

Telekinesis is a high-level client for Amazon Kinesis.

The library provides a high-throughput asynchronous producer and wraps the
[Kinesis Client Library](https://github.com/awslabs/amazon-kinesis-client) to
provide an easy interface for writing consumers.

## Requirements

Telekinesis runs on JRuby 1.7.x or later, with at least Java 6. A minimal set
of producer functionality is available on MRI 1.9.3 or later.

If you want to build from source, you need to have Apache Maven installed.

## Installing

```
gem install telekinesis
```

## Producers

Telekinesis includes two high-level
[Producers](http://docs.aws.amazon.com/kinesis/latest/dev/amazon-kinesis-producers.html).
Records are sent as `key`, `value` pairs of Strings. The key is used by Kinesis
to partition your data into shards. Both keys and values must respect any
Kinesis service [limits](http://docs.aws.amazon.com/kinesis/latest/dev/service-sizes-and-limits.html).

Both producers batch data to Kinesis using the PutRecords API. Batching
increases throughput to Kinesis at the expense of latency by cutting down the
number of API requests made to AWS.

### SyncProducer

The `SyncProducer` makes a call to Kinesis every time `put` or `put_records`
is called. These calls block until the call to Kinesis returns.

Calls to `put` send a single record at a time to Kinesis, where calls to
`put_records` send up to 500 records at a time (it's a Kinesis service limit).
If more than 500 records are passed to `put_records` it groups them into batches
of up to `:send_size` (which defaults to 500) records.

```ruby
producer = Telekinesis::Producer::SyncProducer.create(
  stream: 'my stream',
  send_size: 200,
  credentials: {
    acess_key_id: 'foo',
    secret_access_key: 'bar'
  }
)
```

Putting a single record is as easy as calling `put` and large batches of data
can be sent with `put_all`. Any batch larger than the Kinesis limit of 500
records per PutRecords call will be automatically split up into chunks of 500.

```ruby
# file is a file containing CSV data that looks like:
#
#   "some,very,important,data,with,a,partition_key"
#
lines = file.each_line.map do |line|
  key = line.split(/,/).last
  data = line
  [key, data]
end

# One record at a time
lines.each do |key, data|
  producer.put(key, data)
end

# Manually control your batches
lines.each_slice(200) do |batch|
  producer.put_all(batch)
end

# Go hog wild
producer.put_all(lines.to_a)
```

When something goes wrong and the Kinesis client throws an exception, it bubbles
up as a `Telekinesis::Aws::KinesisError` with the underlying exception acessible
as the `cause.

When some of (but maybe not all of) the records passed to `put\_records` cause
problems, they're returned as an array of
`[key, value, error\_code, error\_message]` tuples.

### AsyncProducer

The `AsyncProducer` queues events interally and uses background threads to send
data to Kinesis. The `AsyncProducer` always uses the `put_records` API call.
Data is sent when a batch reaches the Kinesis PutRecords limit or when the
configured `:send\_every\_ms` timeout is reached so that data doesn't
accumulate in the producer and get stale.

The API for the async producer is looks similar to the sync producer. However,
all `put` and `put\_all` calls return immediately. Since sending (and therefore
failure) happens out of band, you can provide an AsyncProducer with a failure
handler that will be called whenver something bad happens.

```ruby
class MyFailureHandler
  def on_record_failure(kv_pairs_and_errors)
    items = kv_pairs_and_errors.map do |k, v, code, message|
      log_error(code, message)
      [k, v]
    end
    re_enqueue(items)
  end

  def on_kinesis_error(err, items)
    log_exception(err)
    re_enqueue(items)
  end
end

producer = Telekinesis::Producer::AsyncProducer.create(
  stream: 'my stream',
  failure_handler: MyFailureHandler.new,
  send_every_ms: 1500,
  credentials: {
    acess_key_id: 'foo',
    secret_access_key: 'bar'
  }
)
```

> NOTE: The SyncProducer is available on platforms that aren't JRuby.

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

## Prerequisites

* JRuby 1.7.9 or later.
* Apache Maven

## Build

1. Install JRuby 1.7.9 or later, for example with `rbenv` you would:

```
$ rbenv install jruby-1.7.9
```

2. Install Bundler and required Gems.

```
$ gem install bundler
$ bundle install
```

3. Install Apache Maven.

On Ubuntu or related use:

```
$ sudo apt-get install maven
```

The easiest method on OSX is via `brew`.

```
$ sudo brew install maven
```

4. Ensure `JAVA_HOME` is set on OSX.

Ensure your `JAVA_HOME` environment variable is set. In Bash for example
add the following to `~/.bash_profile`.

```
export JAVA_HOME=$(/usr/libexec/java_home)
```

Then run:

```
$ source ~/.bash_profile
```

5. Build the Java shim and jar.

```
$ rake build:ext
```

The `rake build:ext` task builds the Java shim and packages all of the required Java
classes into a single jar. Since bytecode is portable, the JAR is shipped with
the built gem.

6. Build the Gem.

Use the `rake build:gem` task to build the complete gem, uberjar and all.

```
$ rake build:gem
```

# Testing

Telekinesis comes with a small set of unit tests. Run those with plain ol'
`rake test`.

**NOTE:** The java extension *must* be built and installed before you can run
unit tests.

Integration tests coming soon.

