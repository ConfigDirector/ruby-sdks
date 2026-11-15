# frozen_string_literal: true

require_relative "../../../support/client_of_the_scripted_sdk_server"

RSpec.describe ConfigDirector::Internal::Identity::Wrapper do
  include_context "with a client of the scripted SDK server"

  def client_of_the_openfeature_provider(mode:, **client_options)
    client = described_class::OPENFEATURE_SERVER_PROVIDER.create_client(
      "server-sdk-key",
      connection: ConfigDirector::ConnectionOptions.new(mode: mode, timeout: 5, url: sdk_server.url),
      logger: logger, **client_options
    )
    clients_created << client
    client
  end

  it "creates a client that names the OpenFeature provider and its gem's version to the SDK server in streaming mode" do
    stub_const("ConfigDirector::OpenFeature::VERSION", "0.4.2")
    start_init_of(client_of_the_openfeature_provider(mode: "streaming"))

    stream_request = sdk_server.next_stream_request

    expect(stream_request.headers["user-agent"]).to eq("ruby-openfeature-server-provider/0.4.2")
    expect(stream_request.json["metaContext"]).to eq(
      "sdkName" => "ruby-openfeature-server-provider", "sdkVersion" => "0.4.2"
    )
  end

  it "creates a client that names the OpenFeature provider and its gem's version to the SDK server in polling mode" do
    stub_const("ConfigDirector::OpenFeature::VERSION", "0.4.2")
    start_init_of(client_of_the_openfeature_provider(mode: "polling"))

    poll_request = sdk_server.next_poll_request
    poll_request.answer(status: 204)

    expect(poll_request.headers["user-agent"]).to eq("ruby-openfeature-server-provider/0.4.2")
    expect(poll_request.json["metaContext"]).to eq(
      "sdkName" => "ruby-openfeature-server-provider", "sdkVersion" => "0.4.2"
    )
  end

  it "names the version 0.0.0-dev while the gem of the OpenFeature provider is not loaded" do
    start_init_of(client_of_the_openfeature_provider(mode: "streaming"))

    stream_request = sdk_server.next_stream_request

    expect(stream_request.headers["user-agent"]).to eq("ruby-openfeature-server-provider/0.0.0-dev")
    expect(stream_request.json["metaContext"]).to eq(
      "sdkName" => "ruby-openfeature-server-provider", "sdkVersion" => "0.0.0-dev"
    )
  end

  it "names the version of the gem that is loaded when the client is created" do
    stub_const("ConfigDirector::OpenFeature::VERSION", "0.4.2")
    client = client_of_the_openfeature_provider(mode: "streaming")
    stub_const("ConfigDirector::OpenFeature::VERSION", "0.5.0")
    start_init_of(client)

    expect(sdk_server.next_stream_request.headers["user-agent"]).to eq("ruby-openfeature-server-provider/0.4.2")
  end

  it "creates a client with the options create_client takes" do
    values_of_the_watch = Queue.new
    client = client_of_the_openfeature_provider(
      mode: "streaming", metadata: ConfigDirector::Metadata.new(app_name: "storefront", app_version: "1.4.0"),
      hooks: ConfigDirector::ClientHooks.new(client_ready: -> { values_of_the_watch << :client_ready })
    )
    client.watch("day-of-the-week", "Sunday") { |value| values_of_the_watch << value }

    stream_request = initialize_over_a_stream_carrying(
      full_payload_text(configs: [wire_config("day-of-the-week", "Monday")]), client
    )

    expect(stream_request.json["metaContext"]).to include("appName" => "storefront", "appVersion" => "1.4.0")
    expect(Array.new(2) { values_of_the_watch.pop(timeout: 5) }).to eq(["Monday", :client_ready])
  end

  it "rejects what create_client rejects" do
    expect { described_class::OPENFEATURE_SERVER_PROVIDER.create_client(logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "lists the OpenFeature provider only, and takes no other wrapper" do
    expect(described_class.constants).to eq([:OPENFEATURE_SERVER_PROVIDER])
    expect { described_class.new("another-sdk", "AnotherSdk::VERSION") }.to raise_error(NoMethodError)
  end

  it "makes no SDK identity for a name that is not a wrapper it lists" do
    expect { ConfigDirector::Internal::Identity::SdkIdentity.of_the_wrapper("another-sdk") }
      .to raise_error(ArgumentError)
    expect { ConfigDirector::Internal::Identity::SdkIdentity.new("another-sdk", "1.0.0") }
      .to raise_error(NoMethodError)
  end
end
