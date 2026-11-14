# frozen_string_literal: true

require_relative "../support/recording_logger"

RSpec.describe "A client's lifecycle" do
  let(:logger) { RecordingLogger.new }
  let(:client) { ConfigDirector.create_client("server-sdk-key", logger: logger) }

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
end
