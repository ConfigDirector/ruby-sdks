# frozen_string_literal: true

require "pp"
require "configdirector/testing"
require_relative "../support/client_of_the_scripted_sdk_server"

RSpec.describe "What a client shows when it is inspected" do
  include_context "with a client of the scripted SDK server"

  let(:server_sdk_key) { "sdk-0f3c9a7e-kept-secret" }

  def client_with_the_secret_key(mode:)
    client_connecting_to(sdk_server.url, mode: mode, server_sdk_key: server_sdk_key)
  end

  it "shows its connection mode and whether it is ready and closed" do
    client = client_with_the_secret_key(mode: "polling")

    expect(client.inspect).to eq('#<ConfigDirector::ConfigDirectorClient mode="polling" ready=false closed=false>')
  end

  it "shows that it is ready once values arrived" do
    client = client_with_the_secret_key(mode: "streaming")

    initialize_over_a_stream_carrying(full_payload_text, client)

    expect(client.inspect).to eq('#<ConfigDirector::ConfigDirectorClient mode="streaming" ready=true closed=false>')
  end

  it "shows that it is closed after close" do
    client = client_with_the_secret_key(mode: "streaming")
    initialize_over_a_stream_carrying(full_payload_text, client)

    client.close

    expect(client.inspect).to eq('#<ConfigDirector::ConfigDirectorClient mode="streaming" ready=false closed=true>')
  end

  it "shows the mode test for the client of a test client" do
    test_client = ConfigDirector::Testing.create_test_client({ "new-checkout" => true }, logger: logger)
    clients_created << test_client.client

    test_client.client.init

    expect(test_client.client.inspect)
      .to eq('#<ConfigDirector::ConfigDirectorClient mode="test" ready=true closed=false>')
  end

  it "does not show the server SDK key when a streaming client is inspected" do
    client = client_with_the_secret_key(mode: "streaming")
    initialize_over_a_stream_carrying(full_payload_text, client)

    expect(client.inspect).not_to include(server_sdk_key)
  end

  it "does not show the server SDK key when a polling client is inspected" do
    client = client_with_the_secret_key(mode: "polling")
    initialize_with_a_first_poll_answered(client, status: 200, body: full_payload_text)

    expect(client.inspect).not_to include(server_sdk_key)
  end

  it "does not show the server SDK key when a client is pretty printed" do
    client = client_with_the_secret_key(mode: "streaming")
    initialize_over_a_stream_carrying(full_payload_text, client)

    expect(PP.pp(client, +"")).not_to include(server_sdk_key)
  end

  it "does not show the server SDK key when the connection error of a refusal that repeats it is inspected" do
    connection_errors = []
    client = client_with_the_secret_key(mode: "polling")
    client.on(:connection_error) { |event| connection_errors << event }

    initialize_with_a_first_poll_answered(client, status: 401, body: "The key #{server_sdk_key} is unknown.")

    expect(connection_errors.length).to eq(1)
    expect(connection_errors.first.inspect).not_to include(server_sdk_key)
    expect(connection_errors.first.error.inspect).not_to include(server_sdk_key)
  end
end
