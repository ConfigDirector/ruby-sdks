# frozen_string_literal: true

require_relative "../support/recording_logger"

RSpec.describe "A client's watches" do
  let(:logger) { RecordingLogger.new }
  let(:client) { ConfigDirector.create_client("server-sdk-key", logger: logger) }

  it "delivers the value to a watch registered before init during init" do
    values = []
    client.watch("integer-config", 10) { |value| values << value }

    client.init

    expect(values).to eq([42])
  end

  it "does not deliver to a watch when it is registered after init" do
    client.init
    values = []

    client.watch("integer-config", 10) { |value| values << value }

    expect(values).to be_empty
  end

  it "delivers to every watch on the key, in the order they were registered" do
    deliveries = []
    client.watch("integer-config", 10) { |value| deliveries << [:first_watch, value] }
    client.watch("integer-config", 10) { |value| deliveries << [:second_watch, value] }

    client.init

    expect(deliveries).to eq([[:first_watch, 42], [:second_watch, 42]])
  end

  it "evaluates a watch for its own context" do
    values = []
    client.watch("day-of-the-week-config", "Sunday", ConfigDirector::Context.new(traits: { plan: "pro" })) do |value|
      values << value
    end

    client.init

    expect(values).to eq(["Tuesday"])
  end

  it "raises when a watch is given no block" do
    expect { client.watch("integer-config", 10) }.to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises when a watch is given a nil in-code default value" do
    expect { client.watch("integer-config", nil) { |_value| nil } }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises when a watch is given a context that is not a Context" do
    expect { client.watch("integer-config", 10, { id: "user-123" }) { |_value| nil } }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "removes only the watch whose subscription is closed, even when another watch shares its callback" do
    values = []
    record = ->(value) { values << value }
    pro_context = ConfigDirector::Context.new(traits: { plan: "pro" })
    client.watch("day-of-the-week-config", "Sunday", &record)
    subscription = client.watch("day-of-the-week-config", "Sunday", pro_context, &record)

    subscription.close
    client.init

    expect(values).to eq(["Monday"])
  end

  it "removes the first watch on the key with the callback unwatch is given" do
    deliveries = []
    record = ->(value) { deliveries << [:shared_callback, value] }
    client.watch("integer-config", 10, &record)
    client.watch("integer-config", 10, &record)
    client.watch("integer-config", 10) { |value| deliveries << [:other_callback, value] }

    client.unwatch("integer-config", record)
    client.init

    expect(deliveries).to eq([[:shared_callback, 42], [:other_callback, 42]])
  end

  it "removes every watch on the key, and only on that key, when unwatch is given no callback" do
    deliveries = []
    client.watch("integer-config", 10) { |value| deliveries << value }
    client.watch("integer-config", 20) { |value| deliveries << value }
    client.watch("float-config", 1.5) { |value| deliveries << value }

    client.unwatch("integer-config")
    client.init

    expect(deliveries).to eq([26.0])
  end

  it "removes every watch with unwatch_all" do
    deliveries = []
    client.watch("integer-config", 10) { |value| deliveries << value }
    client.watch("float-config", 1.5) { |value| deliveries << value }

    client.unwatch_all
    client.init

    expect(deliveries).to be_empty
  end

  it "returns nil from unwatch without a callback" do
    client.watch("integer-config", 10) { |_value| nil }

    expect(client.unwatch("integer-config")).to be_nil
  end

  it "returns nil from unwatch with a callback" do
    record = ->(_value) {}
    client.watch("integer-config", 10, &record)

    expect(client.unwatch("integer-config", record)).to be_nil
  end

  it "returns nil from unwatch_all" do
    client.watch("integer-config", 10) { |_value| nil }

    expect(client.unwatch_all).to be_nil
  end
end
