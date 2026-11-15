# frozen_string_literal: true

require "weakref"
require_relative "../support/recording_logger"
require_relative "../support/sdk_server_serving_the_sample_configs"

RSpec.describe "A client's lifecycle" do
  include_context "with an SDK server that serves the sample configs"

  let(:logger) { RecordingLogger.new }
  let(:client) { client_of_the_sample_configs(logger: logger) }

  it "is not ready before init" do
    expect(client.ready?).to be(false)
    expect(client.closed?).to be(false)
  end

  it "returns the in-code default value before init" do
    evaluation = client.evaluate("integer-config", 10)

    expect(evaluation.value).to eql(10)
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("client-not-ready")
  end

  it "is ready after init" do
    client.init

    expect(client.ready?).to be(true)
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "stays ready when init is called again" do
    client.init
    client.init

    expect(client.ready?).to be(true)
    expect(client.get_value("integer-config", 10)).to eql(42)
  end

  it "is closed and not ready after close" do
    client.init

    client.close

    expect(client.closed?).to be(true)
    expect(client.ready?).to be(false)
  end

  it "can be closed twice" do
    client.init

    client.close
    client.close

    expect(client.closed?).to be(true)
  end

  it "can be closed without having been initialized" do
    client.close

    expect(client.closed?).to be(true)
  end

  it "returns the in-code default value after close" do
    client.init
    client.close

    evaluation = client.evaluate("integer-config", 10)

    expect(evaluation.value).to eql(10)
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("client-not-ready")
  end

  it "returns no configs after close" do
    client.init
    client.close

    expect(client.get_all_configs).to eq({})
  end

  it "raises when init is called after close" do
    client.init
    client.close

    expect { client.init }.to raise_error(ConfigDirector::ConfigDirectorValidationError)
    expect(client.ready?).to be(false)
  end

  it "is held by nothing in the SDK when it is offline, so its logger can be garbage collected without a close" do
    logger_of_an_offline_client = Thread.new do
      logger_of_the_client = RecordingLogger.new
      ConfigDirector.create_client(
        connection: ConfigDirector::ConnectionOptions.new(mode: "offline"), logger: logger_of_the_client
      ).init

      WeakRef.new(logger_of_the_client)
    end.value

    GC.start

    expect(logger_of_an_offline_client.weakref_alive?).to be_falsy
  end

  it "is held by nothing in the SDK once it is closed, so its logger can be garbage collected",
     unless: Gem::Version.new(RUBY_VERSION) < Gem::Version.new("4.0") do
    url = sdk_server.url
    logger_of_a_closed_client = Thread.new do
      logger_of_the_client = RecordingLogger.new
      closed_client = ConfigDirector.create_client(
        "server-sdk-key", connection: ConfigDirector::ConnectionOptions.new(url: url), logger: logger_of_the_client
      )
      closed_client.init
      closed_client.close

      WeakRef.new(logger_of_the_client)
    end.value

    GC.start

    expect(logger_of_a_closed_client.weakref_alive?).to be_falsy
  end
end
