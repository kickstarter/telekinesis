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

When some of (but maybe not all of) the records passed to `put_records` cause
problems, they're returned as an array of
`[key, value, error_code, error_message]` tuples.

> NOTE: The SyncProducer is available on any platform.

### AsyncProducer

The `AsyncProducer` queues events interally and uses background threads to send
data to Kinesis. The `AsyncProducer` always uses the `put_records` API call.
Data is sent when a batch reaches the Kinesis PutRecords limit or when the
configured `:send_every_ms` timeout is reached so that data doesn't
accumulate in the producer and get stale.

The API for the async producer is looks similar to the sync producer. However,
all `put` and `put_all` calls return immediately. Since sending (and therefore
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

> NOTE: The AsyncProducer is only available on JRuby.

## Consumers

### DistributedConsumer

The DistributedConsumer is a wrapper around Amazon's [Kinesis Client Library
(KCL)](http://docs.aws.amazon.com/kinesis/latest/dev/kinesis-record-processor-app.html#kinesis-record-processor-overview-kcl).
Each DistributedConsumer is part of a group of consumers (an "application") that
runs on one or more machines. Each consumer gets labelled with a unique id (more
on that later) and attempts to distribute work evenly between all consumers
that are part of the same application. The KCL uses DynamoDB to do all of this
coordination and work sharing.

To actually get at the data you're consuming with this client, create a [record
processor](http://docs.aws.amazon.com/kinesis/latest/dev/kinesis-record-processor-implementation-app-java.html#kinesis-record-processor-implementation-interface-java).
The DistributedConsumer creates a new record processor for each shard. Each
processor only deals with the records from a single shard.

> NOTE: Since `initialize` is both a reserved method in Ruby and a part of the
> KCL's IRecordProcessor interface, Telekinesis comes with a shim that replaces
> `initialize` with `init`.

After they're created, Record Processors are initialized with the shard they're
processing and then handed an enumerable of [Records](http://docs.aws.amazon.com/AWSJavaSDK/latest/javadoc/index.html?com/amazonaws/services/kinesis/AmazonKinesisClient.html)
and a checkpointer (more on that later) every time the client detects new data
to process.

Defining and creating a simple processor might look like:

```ruby
class MyProcessor
  def init(shard_id)
    @shard_id = shard_id
    $stderr.puts "started #{@shard_id}"
  end

  def process_records(records, checkpointer)
    records.each {|r| puts String.from_java_bytes(r.data.array) }
  end

  def shutdown
    $stderr.puts "shutting down #{@shard_id}"
  end
end

Telekinesis::Consumer::DistributedConsumer.new(stream: 'some-events', app: 'example') do
  MyProcessor.new
end
```

To make defining record processors easier, Telekinesis comes with a `Block`
processor that passes a block to `process_records`. Use this if you don't need
to do any fancy startup or shutdown in your processors.

```ruby
Telekinesis::Consumer::DistributedConsumer.new(stream: 'some-events', app: 'example') do
  Telekinesis::Consumer::Block.new do |records, checkpointer|
    records.each {|r| puts String.from_java_bytes(r.data.array) }
  end
end
```

## Java client logging

If you're running on JRuby, the AWS Java SDK can be extremely noisy and hard
to control, since it logs through java.util.logging.

Telekinesis comes with a shim that can silence all of that logging or redirect
it to a Ruby Logger of your choice. This isn't fine-grained control - you're
capturing or disabling ALL logging from any Java dependency that uses
java.util.logging - so use it with care.

To entirely disable logging:

```ruby
Telekinesis::Logging.disable_java_logging
```

To capture all logging and send it through a Ruby logger:

```ruby
Telekinesis::Logging.capture_java_logging(Logger.new($stderr))
```

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

