## Looking for Maintainers

We're not actively maintaining this project. If you're interested in maintaining it, please post a comment on [this issue](https://github.com/kickstarter/telekinesis/issues/22).

## Table of Contents

- [Telekinesis](#telekinesis)
  - [Requirements](#requirements)
  - [Installing](#installing)
  - [Producers](#producers)
    - [SyncProducer](#syncproducer)
    - [AsyncProducer](#asyncproducer)
  - [Consumers](#consumers)
    - [KCL](#kcl)
      - [Client State](#client-state)
      - [Errors while processing records](#errors-while-processing-records)
      - [Checkpoints and `INITIAL_POSITION_IN_STREAM`](#checkpoints-and-initial_position_in_stream)
  - [Java client logging](#java-client-logging)
  - [](#)
- [Building](#building)
  - [Prerequisites](#prerequisites)
  - [Build](#build)
- [Testing](#testing)
- [License](#license)

# Telekinesis

Telekinesis is a high-level client for Amazon Kinesis.

The library provides a high-throughput asynchronous producer and wraps the
[Kinesis Client Library](https://github.com/awslabs/amazon-kinesis-client) to
provide an easy interface for writing consumers.

## Requirements

Telekinesis runs on JRuby 1.7.x or later, with at least Java 6.

If you want to build from source, you need to have Apache Maven installed.

## Installing

```
gem install telekinesis
```

## Producers

Telekinesis includes two high-level
[Producers](http://docs.aws.amazon.com/kinesis/latest/dev/amazon-kinesis-producers.html).

Telekinesis assumes that records are `[key, value]` pairs of strings. The key
*must* be a string as enforced by Kinesis itself. Keys are used by the service
to partition data into shards. Values can be any old blob of data, but for
simplicity, Telekinesis expects strings.

Both keys and values should respect any Kinesis
[limits](http://docs.aws.amazon.com/kinesis/latest/dev/service-sizes-and-limits.html).
and all of the [restrictions](http://docs.aws.amazon.com/kinesis/latest/APIReference/API_PutRecord.html)
in the PutRecords API documentation.

### SyncProducer

The `SyncProducer` sends data to Kinesis every time `put` or `put_all`
is called. These calls will block until the call to Kinesis returns.


```ruby
require 'telekinesis'

producer = Telekinesis::Producer::SyncProducer.create(
  stream: 'my stream',
  credentials: {
    access_key_id: 'foo',
    secret_access_key: 'bar'
  }
)
```

Calls to `put` send a single record at a time to Kinesis, where calls to
`put_all` can send up to 500 records at a time, which is the Kinesis service
limit.  If more than 500 records are passed to `put_all` they're grouped into
batches and sent.

> NOTE: To send fewer records to Kinesis at a time when using `put_all`, you
> can adjust the `:send_size` parameter in the `create` method.

Using `put_all` over `put` is recommended if you have any way to batch your
data. Since Kinesis has an HTTP API and often has high latency, it tends to make
sense to try and increase throughput as much as possible by batching data.

```ruby
# file is an instance of File containing CSV data that looks like:
#
#   "some,very,important,data,with,a,partition_key"
#
lines = file.lines.map do |line|
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
up as a `Telekinesis::Aws::KinesisError` with the underlying exception accessible
as the `cause` field.

When some of (but maybe not all of) the records passed to `put_all` cause
problems, they're returned as an array of
`[key, value, error_code, error_message]` tuples.

### AsyncProducer

The `AsyncProducer` queues events interally and uses background threads to send
data to Kinesis.  Data is sent when a batch reaches the Kinesis limit of 500,
when the producer's timeout is reached, or when the producer is shut down.

> NOTE: You can configure the size at which a batch is sent by passing the
> `:send_size` parameter to create. The producer's internal timeout can be
> set by using the `:send_every_ms` parameter.

The API for the `AsyncProducer` is looks similar to the `SyncProducer`. However,
all `put` and `put_all` calls return immediately. Both `put` and `put_all`
return `true` if the producer enqueued the data for sending later, and `false`
if the producer is not accepting data for any reason. If the producer's internal
queue fill up, calls to `put` and `put_all` will block.

Since sending (and therefore failures) happen in a different thread, you can
provide an `AsyncProducer` with a failure handler that's called whenever
something bad happens.

```ruby
require 'telekinesis'

class MyFailureHandler
  def on_record_failure(kv_pairs_and_errors)
    items = kv_pairs_and_errors.map do |k, v, code, message|
      maybe_log_error(code, message)
      [k, v]
    end
    save_for_later(items)
  end

  def on_kinesis_error(err, items)
    log_exception(err.cause)
    save_for_later(items)
  end
end

producer = Telekinesis::Producer::AsyncProducer.create(
  stream: 'my stream',
  failure_handler: MyFailureHandler.new,
  send_every_ms: 1500,
  credentials: {
    access_key_id: 'foo',
    secret_access_key: 'bar'
  }
)
```

## Consumers

### KCL

`Telekinesis::Consumer::KCL` is a wrapper around Amazon's [Kinesis Client
Library (also called the KCL)](http://docs.aws.amazon.com/kinesis/latest/dev/kinesis-record-processor-app.html#kinesis-record-processor-overview-kcl).

Each KCL instance is part of a group of consumers that make up an
_application_. An application can be running on any number of hosts in any
number of processes.  Consumers identify themself uniquely within an
application by specifying a `worker_id`.

All of the consumers within an application attempt to distribute work evenly
between themselves by coordinating through a DynamoDB table. This coordination
ensures that a single consumer processes each shard, and that if one consumer
fails for any reason, another consumer can pick up from the point at which it
last checkpointed.

This is all part of the official AWS library! Telekinesis just makes it easier
to use from JRuby.

Each client has to know how to process all the data it's
retreiving from Kinesis. That's done by creating a [record
processor](http://docs.aws.amazon.com/kinesis/latest/dev/kinesis-record-processor-implementation-app-java.html#kinesis-record-processor-implementation-interface-java)
and telling a `KCL` how to create a processor when it becomes
responsible for a shard.

We highly recommend reading the [official
docs](http://docs.aws.amazon.com/kinesis/latest/dev/kinesis-record-processor-implementation-app-java.html#kinesis-record-processor-implementation-interface-java)
on implementing the `IRecordProcessor` interface before you continue.

> NOTE: Since `initialize` is a reserved method, Telekinesis takes care of
> calling your `init` method whenever the KCL calls `IRecordProcessor`'s
> `initialize` method.

> NOTE: Make sure you read the Kinesis Record Processor documentation carefully.
> Failures, checkpoints, and shutting require some attention. More on that later.

After it is created, a record processor is initialized with the ID of the shard
it's processing, and handed an enumerable of
[Records](http://docs.aws.amazon.com/AWSJavaSDK/latest/javadoc/index.html?com/amazonaws/services/kinesis/AmazonKinesisClient.html) and a checkpointer (see below) every time the consumer detects new data to
process.

Defining and creating a simple processor might look like:

```ruby
require 'telekinesis'

class MyProcessor
  def init(init_input)
    @shard_id = init_input.shard_id
    $stderr.puts "Started processing #{@shard_id}"
  end

  def process_records(process_records_input)
    process_records_input.records.each do
      |r| puts "key=#{r.partition_key} value=#{String.from_java_bytes(r.data.array)}"
    end
  end

  def shutdown
    $stderr.puts "Shutting down #{@shard_id}"
  end
end

worker = Telekinesis::Consumer::KCL.new(stream: 'some-events', app: 'example') do
  MyProcessor.new
end

worker.run
```

To make defining record processors easier, Telekinesis comes with a `Block`
processor that lets you use a block to specify your `process_records` method.
Use this if you don't need to do any explicit startup or shutdown in a record
processor.

```ruby
require 'telekinesis'

worker = Telekinesis::Consumer::KCL.new(stream: 'some-events', app: 'example') do
  Telekinesis::Consumer::Block.new do |records, checkpointer, millis_behind|
    records.each {|r| puts "key=#{r.partition_key} value=#{String.from_java_bytes(r.data.array)}" }
  end
end

worker.run
```

Once you get into building a client application, you'll probably want
to know about some of the following advanced tips and tricks.

#### Client State

Each KCL Application gets its own DynamoDB table that stores all of this state.
The `:application` name is used as the DynamoDB table name, so beware of
namespace collisions if you use DynamoDB on its own. Altering or reseting any
of this state involves manually altering the application's Dynamo table.

#### Errors while processing records

When a call to `process_records` fails, the KCL expects you to handle the
failure and try to reprocess. If you let an exception escape, it happily moves
on to the next batch of records from Kinesis and will let you checkpoint further
on down the road.

From the [official docs](http://docs.aws.amazon.com/kinesis/latest/dev/kinesis-record-processor-implementation-app-java.html):

> The KCL relies on processRecords to handle any exceptions that arise from
> processing the data records. If an exception is thrown from processRecords,
> the KCL skips over the data records that were passed prior to the exception;
> that is, these records are not re-sent to the record processor that threw the
> exception or to any other record processor in the application.

The moral of the story is that you should be absolutely sure you catch any
exceptions that get thrown in your `process_records` implementation. If you
don't, you can (silently) drop data on the floor.

If something terrible happens and you can't attempt to re-read the list of
records and re-do whatever work you needed to do in process records, we've been
advised by the Kinesis team that killing the entire JVM that's running the
worker is the safest thing to do. On restart, the consumer (or another consumer
in the application group) will pick up the orphaned shards and attempt to
restart from the last available checkpoint.

#### Checkpoints and `INITIAL_POSITION_IN_STREAM`

The second object passed to `process_records` is a checkpointer. This can be
used to checkpoint all records that have been passed to the processor so far
(by just calling `checkpointer.checkpoint`) or up to a particular sequence
number (by calling `checkpointer.checkpoint(record.sequence_number)`).

While a `KCL` consumer can be initialized with an `:initial_position_in_stream`
option, any existing checkpoint for a shard will take precedent over that
value. Furthermore, any existing STATE in DynamoDB will take precedent, so if
you start a consumer with `initial_position_in_stream: 'LATEST'` and then
restart with `initial_position_in_stream: 'TRIM_HORIZON'` you still end up
starting from `LATEST`.

## Java client logging

The AWS Java SDK can be extremely noisy and hard to control, since it logs
through `java.util.logging`.

Telekinesis comes with a shim that can silence all of that logging or redirect
it to a Ruby Logger of your choice. This isn't fine-grained control - you're
capturing or disabling ALL logging from any Java dependency that uses
`java.util.logging` - so use it with care.

To entirely disable logging:

```ruby
Telekinesis::Logging.disable_java_logging
```

To capture all logging and send it through a Ruby logger:

```ruby
Telekinesis::Logging.capture_java_logging(Logger.new($stderr))
```

----

# Building

## Prerequisites

* JRuby 1.7.9 or later.
* Apache Maven

## Build

Install JRuby 1.7.9 or later, for example with `rbenv` you would:

```
$ rbenv install jruby-1.7.9
```

Install Bundler and required Gems.

```
$ gem install bundler
$ bundle install
```

Install Apache Maven.

On Ubuntu or related use:

```
$ sudo apt-get install maven
```

The easiest method on OSX is via `brew`.

```
$ sudo brew install maven
```

Ensure `JAVA_HOME` is set on OSX.

Ensure your `JAVA_HOME` environment variable is set. In Bash for example
add the following to `~/.bash_profile`.

```
export JAVA_HOME=$(/usr/libexec/java_home)
```

Then run:

```
$ source ~/.bash_profile
```

Build the Java shim and jar.

```
$ rake ext:build
```

The `rake ext:build` task builds the Java shim and packages all of the required Java
classes into a single jar. Since bytecode is portable, the JAR is shipped with
the built gem.

Build the Gem.

Use the `rake gem:build` task to build the complete gem, uberjar and all.

```
$ rake gem:build
```

# Testing

Telekinesis comes with a small set of unit tests. Run those with plain ol'
`rake test`.

> NOTE: The Java extension *must* be built and installed before you can run
> unit tests.

Integration tests coming soon.


# License

Copyright Kickstarter, PBC.

Released under an [MIT License](http://opensource.org/licenses/MIT).

