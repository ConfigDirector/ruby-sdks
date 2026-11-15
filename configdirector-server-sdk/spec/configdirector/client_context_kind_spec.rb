# frozen_string_literal: true

require_relative "../support/recording_logger"
require_relative "../support/sdk_server_serving_the_sample_configs"

RSpec.describe "A context's kind" do
  include_context "with an SDK server that serves the sample configs"

  let(:logger) { RecordingLogger.new }
  let(:client) { client_of_the_sample_configs(logger: logger) }

  before { client.init }

  it "evaluates a context of the kind device" do
    device = ConfigDirector::Context.new(id: "device-1", kind: "device")

    evaluation = client.evaluate("temporary-feature-flag", false, device)

    expect(evaluation.value).to be(true)
    expect(evaluation.context).to be(device)
    expect(logger.messages_at(:error)).to be_empty
  end

  it "evaluates a context whose kind has 64 characters" do
    context = ConfigDirector::Context.new(id: "tenant-1", kind: "t" * 64)

    expect(client.evaluate("temporary-feature-flag", false, context).context).to be(context)
    expect(logger.messages_at(:error)).to be_empty
  end

  it "evaluates a context whose kind uses digits, a dash and an underscore" do
    context = ConfigDirector::Context.new(id: "listing-1", kind: "listing_2-b")

    expect(client.evaluate("temporary-feature-flag", false, context).context).to be(context)
    expect(logger.messages_at(:error)).to be_empty
  end

  it "ignores the whole context when its kind is Device" do
    device = ConfigDirector::Context.new(id: "device-1", kind: "Device", traits: { "plan" => "pro" })

    flag = client.evaluate("temporary-feature-flag", true, device)
    day = client.evaluate("day-of-the-week-config", "Sunday", device)

    expect(flag.value).to be(false)
    expect(flag.reason).to eq("rollout-skipped-no-identifier")
    expect(flag.context).to be_nil
    expect(day.value).to eq("Monday")
  end

  it "logs one error for a context with the kind Device" do
    client.evaluate("temporary-feature-flag", true, ConfigDirector::Context.new(id: "device-1", kind: "Device"))

    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to include("Device")
  end

  it "logs one error for the same invalid kind given twice" do
    2.times do
      client.get_value("temporary-feature-flag", true, ConfigDirector::Context.new(id: "device-1", kind: "Device"))
    end

    expect(logger.messages_at(:error).length).to eq(1)
  end

  it "logs an error for each different invalid kind" do
    client.get_value("temporary-feature-flag", true, ConfigDirector::Context.new(kind: "Device"))
    client.get_value("temporary-feature-flag", true, ConfigDirector::Context.new(kind: "Tenant"))

    expect(logger.messages_at(:error).length).to eq(2)
  end

  it "logs one more error after 20 different invalid kinds, and then none" do
    22.times do |number|
      client.get_value("temporary-feature-flag", true, ConfigDirector::Context.new(kind: "Kind #{number}"))
    end

    expect(logger.messages_at(:error).length).to eq(21)
  end

  it "ignores a context with an empty kind" do
    evaluation = client.evaluate("temporary-feature-flag", true, ConfigDirector::Context.new(id: "user-1", kind: ""))

    expect(evaluation.context).to be_nil
    expect(logger.messages_at(:error).length).to eq(1)
  end

  it "ignores a context whose kind has 65 characters" do
    context = ConfigDirector::Context.new(id: "user-1", kind: "k" * 65)

    expect(client.evaluate("temporary-feature-flag", true, context).context).to be_nil
    expect(logger.messages_at(:error).length).to eq(1)
  end

  it "ignores a context whose kind ends with a line break" do
    context = ConfigDirector::Context.new(id: "user-1", kind: "device\n")

    expect(client.evaluate("temporary-feature-flag", true, context).context).to be_nil
  end

  it "ignores a context whose kind has a letter outside a to z" do
    context = ConfigDirector::Context.new(id: "user-1", kind: "café")

    expect(client.evaluate("temporary-feature-flag", true, context).context).to be_nil
  end

  it "ignores a context whose kind is a Symbol" do
    context = ConfigDirector::Context.new(id: "user-1", kind: :device)

    expect(client.evaluate("temporary-feature-flag", true, context).context).to be_nil
    expect(logger.messages_at(:error).length).to eq(1)
  end

  it "ignores a context whose kind is not valid UTF-8" do
    context = ConfigDirector::Context.new(id: "user-1", kind: "dev\xFFice")

    expect(client.evaluate("temporary-feature-flag", true, context).context).to be_nil
    expect(logger.messages_at(:error).length).to eq(1)
  end

  it "logs no more than the first 128 characters of an invalid kind" do
    client.get_value("temporary-feature-flag", true, ConfigDirector::Context.new(kind: "K#{"x" * 127}tail"))

    expect(logger.messages_at(:error).first).to include("K#{"x" * 127}")
    expect(logger.messages_at(:error).first).not_to include("K#{"x" * 127}t")
  end

  it "ignores a context with an invalid kind in get_all_configs and logs one error" do
    device = ConfigDirector::Context.new(id: "device-1", kind: "Device")

    states = client.get_all_configs(context: device)

    expect(states.fetch("temporary-feature-flag").value).to eq("false")
    expect(logger.messages_at(:error).length).to eq(1)
  end
end
