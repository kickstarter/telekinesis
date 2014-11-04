require_relative 'test_helper'

class ConfigsTest < Minitest::Test
  context "building consumer config" do
    should "fail without app name" do
      assert_raises(ArgumentError) {
        Telekinesis::Config.consumer_config({stream: "hi", worker_id: "one", creds: {type: "default"}})
      }
    end

    should "fail without stream name" do
      assert_raises(ArgumentError) {
        Telekinesis::Config.consumer_config({app: "hi", worker_id: "one", creds: {type: "default"}})
      }
    end

    should "fail without worker id" do
      assert_raises(ArgumentError) {
        Telekinesis::Config.consumer_config({stream: "hi", app: "hi", creds: {type: "default"}})
      }
    end

    should "fail without creds" do
      assert_raises(ArgumentError) {
        Telekinesis::Config.consumer_config({app: "hi", stream: "hi", worker_id: "one"})
      }
    end

    should "fail on unexpected credentials types" do
      assert_raises(ArgumentError) {
        Telekinesis::Config.consumer_config({app: "hi", stream: "hi", creds: {}})
      }
      assert_raises(ArgumentError) {
        Telekinesis::Config.consumer_config({app: "hi", stream: "hi", creds: {type: "garbage"}})
      }
    end


    should "build with only required args" do
      cfg = Telekinesis::Config.consumer_config(
        app: "my-app",
        stream: "an-stream",
        worker_id: "hostname.123",
        creds: {type: "default"}
      )
      assert_equal("my-app", cfg.get_application_name)
      assert_equal("an-stream", cfg.get_stream_name)
      assert_equal("hostname.123", cfg.get_worker_identifier)
      assert_equal(DefaultAWSCredentialsProviderChain.java_class,
                   cfg.get_kinesis_credentials_provider.java_class)
    end

    should "set values as expected" do
      opts = {
        initial_position_in_stream: 'TRIM_HORIZON',
        task_backoff_time_millis: 1000
      }
      cfg = Telekinesis::Config.consumer_config(
        app: "my-app",
        stream: "an-stream",
        worker_id: "hostname.123",
        creds: {type: "default"},
        options: opts
      )
      assert_equal("my-app", cfg.get_application_name)
      assert_equal("an-stream", cfg.get_stream_name)
      assert_equal("hostname.123", cfg.get_worker_identifier)
      opts.each do |k, v|
        getter = "get_#{k.to_sym}"
        assert_equal(v.to_s, cfg.send(getter).to_s)
      end
    end
  end
end
