# frozen_string_literal: true

require "tmpdir"
require_relative "../../../../configdirector-server-sdk/spec/support/waiting"
require_relative "../../support/provider_over_the_scripted_sdk_server"

RSpec.describe "The startup of a ConfigDirector OpenFeature provider" do
  include_context "with a provider over the scripted SDK server"

  let(:no_config_in_time) do
    "No config arrived from ConfigDirector within the connection timeout. " \
      "Flags resolve to their in-code default values until config arrives."
  end

  def events_sent(event_type)
    events = Queue.new
    open_feature.add_handler(event_type, ->(event_details) { events << event_details })
    events
  end

  def status
    open_feature.build_client.provider_status
  end

  def registration_without_config_in_time
    registering = start_registering(provider_connecting_to_the_sdk_server(timeout: 0.5))
    stream_request = sdk_server.next_stream_request
    stream_request.open_event_stream
    registering.join(10)

    [registering, stream_request]
  end

  def wait_until_the_client_is_ready
    Waiting.wait_up_to(5) do
      logger.messages_at(:debug).include?(
        "[ConfigDirectorClient] Received initial payload from the server, client is ready"
      )
    end
  end

  def greeting_read_through_open_feature
    open_feature.build_client.fetch_string_value(flag_key: "greeting", default_value: "in-code")
  end

  describe "when config arrives within the connection timeout" do
    it "reports Ready once and leaves OpenFeature without a deprecation warning" do
      open_feature.logger = RecordingLogger.new
      ready_events = events_sent(OpenFeature::SDK::ProviderEvent::PROVIDER_READY)

      register_over_a_stream_carrying(provider_connecting_to_the_sdk_server, wire_config("greeting", "hello"))

      expect(status).to eq("READY")
      expect(ready_events.size).to eq(1)
      expect(open_feature.logger.messages_at(:warn)).to eq([])
    end
  end

  describe "when no config arrives within the connection timeout" do
    it "fails set_provider_and_wait with PROVIDER_NOT_READY" do
      registering, = registration_without_config_in_time

      registration_error = registering.value
      expect(registration_error).to be_a(OpenFeature::SDK::ProviderInitializationError)
      expect(registration_error.error_code).to eq("PROVIDER_NOT_READY")
      expect(registration_error.original_error).to be_a(OpenFeature::SDK::EvaluationError)
      expect(registration_error.original_error.message).to eq(no_config_in_time)
    end

    it "reports Error with PROVIDER_NOT_READY and the reason" do
      error_events = events_sent(OpenFeature::SDK::ProviderEvent::PROVIDER_ERROR)

      registration_without_config_in_time

      expect(status).to eq("ERROR")
      expect(error_events.size).to eq(1)
      expect(error_events.pop).to eq(
        provider_name: "ConfigDirectorProvider", error_code: "PROVIDER_NOT_READY", message: no_config_in_time
      )
    end

    it "resolves reads to the in-code default value with PROVIDER_NOT_READY" do
      registration_without_config_in_time

      details = open_feature.build_client.fetch_string_details(flag_key: "greeting", default_value: "in-code")

      expect(details.value).to eq("in-code")
      expect(details.reason).to eq("ERROR")
      expect(details.error_code).to eq("PROVIDER_NOT_READY")
      expect(details.error_message).to eq("ConfigDirector has not delivered config state yet.")
    end

    it "reports Ready once when config arrives later, and resolves reads to its values" do
      _, stream_request = registration_without_config_in_time
      ready_events = events_sent(OpenFeature::SDK::ProviderEvent::PROVIDER_READY)

      stream_request.send_event(full_payload_text(configs: [wire_config("greeting", "hello")]))
      wait_until_the_client_is_ready

      expect(status).to eq("READY")
      expect(ready_events.size).to eq(1)
      expect(greeting_read_through_open_feature).to eq("hello")
    end

    it "reports Ready after the Error when config arrives while the Error is being reported" do
      provider = provider_connecting_to_the_sdk_server(timeout: 0.5)
      lifecycle_events = Queue.new
      stream_request = nil
      open_feature.add_handler(
        OpenFeature::SDK::ProviderEvent::PROVIDER_ERROR,
        lambda { |_event_details|
          lifecycle_events << :error
          stream_request.send_event(full_payload_text(configs: [wire_config("greeting", "hello")]))
          wait_until_the_client_is_ready
        }
      )
      open_feature.add_handler(
        OpenFeature::SDK::ProviderEvent::PROVIDER_READY, ->(_event_details) { lifecycle_events << :ready }
      )

      registering = start_registering(provider)
      stream_request = sdk_server.next_stream_request
      stream_request.open_event_stream
      registering.join(10)

      expect(status).to eq("READY")
      expect(Array.new(lifecycle_events.size) { lifecycle_events.pop }).to eq(%i[error ready])
    end
  end

  describe "when ConfigDirector refuses the server SDK key" do
    it "fails set_provider_and_wait with PROVIDER_NOT_READY and reports Error" do
      registering = start_registering(provider_connecting_to_the_sdk_server)
      sdk_server.next_stream_request.answer(status: 401)

      registration_error = registering.value
      expect(registration_error).to be_a(OpenFeature::SDK::ProviderInitializationError)
      expect(registration_error.error_code).to eq("PROVIDER_NOT_READY")
      expect(status).to eq("ERROR")
    end
  end

  describe "in offline mode" do
    it "resolves reads to the offline values without a server SDK key" do
      provider = ConfigDirector::OpenFeature::ConfigDirectorProvider.new(
        connection: ConfigDirector::ConnectionOptions.new(mode: "offline", values: { "greeting" => "hello" }),
        logger: logger
      )

      open_feature.set_provider_and_wait(provider)

      expect(greeting_read_through_open_feature).to eq("hello")
    end

    it "fails set_provider_and_wait with the SDK's error and reports Error when the offline values cannot be loaded" do
      error_events = events_sent(OpenFeature::SDK::ProviderEvent::PROVIDER_ERROR)
      provider = ConfigDirector::OpenFeature::ConfigDirectorProvider.new(
        connection: ConfigDirector::ConnectionOptions.new(
          mode: "offline", file: File.join(Dir.tmpdir, "no-configdirector-values-here.json")
        ),
        logger: logger
      )

      expect { open_feature.set_provider_and_wait(provider) }.to raise_error(
        OpenFeature::SDK::ProviderInitializationError
      ) do |error|
        expect(error.error_code).to eq("GENERAL")
        expect(error.original_error).to be_a(ConfigDirector::ConfigDirectorInitializationError)
      end
      expect(status).to eq("ERROR")
      expect(error_events.pop.fetch(:error_code)).to eq("GENERAL")
    end
  end

  it "closes its client when OpenFeature shuts down, which reports the client's telemetry" do
    client = open_feature_client_serving(wire_config("greeting", "hello"))
    client.fetch_string_value(flag_key: "greeting", default_value: "in-code")

    open_feature.shutdown

    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 5)).to be(true)
  end
end
