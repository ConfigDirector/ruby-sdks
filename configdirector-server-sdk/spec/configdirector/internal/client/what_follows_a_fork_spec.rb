# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Client::WhatFollowsAFork do
  it "restarts the connection of a streaming client" do
    what_follows = described_class.for_a_client_with(
      mode: "streaming", connection_opened: true, closed: false, connection_failed_unrecoverably: false
    )

    expect(what_follows).to eq(:restart_the_connection)
  end

  it "restarts the connection of a polling client" do
    what_follows = described_class.for_a_client_with(
      mode: "polling", connection_opened: true, closed: false, connection_failed_unrecoverably: false
    )

    expect(what_follows).to eq(:restart_the_connection)
  end

  it "has nothing to restart for an offline client" do
    what_follows = described_class.for_a_client_with(
      mode: "offline", connection_opened: true, closed: false, connection_failed_unrecoverably: false
    )

    expect(what_follows).to eq(:nothing_to_restart)
  end

  it "has nothing to restart for a client whose connection was not opened yet" do
    what_follows = described_class.for_a_client_with(
      mode: "streaming", connection_opened: false, closed: false, connection_failed_unrecoverably: false
    )

    expect(what_follows).to eq(:nothing_to_restart)
  end

  it "has nothing to restart for a closed client" do
    what_follows = described_class.for_a_client_with(
      mode: "streaming", connection_opened: true, closed: true, connection_failed_unrecoverably: false
    )

    expect(what_follows).to eq(:nothing_to_restart)
  end

  it "has nothing to restart for a client whose connection the SDK server refused for good" do
    what_follows = described_class.for_a_client_with(
      mode: "polling", connection_opened: true, closed: false, connection_failed_unrecoverably: true
    )

    expect(what_follows).to eq(:nothing_to_restart)
  end
end
