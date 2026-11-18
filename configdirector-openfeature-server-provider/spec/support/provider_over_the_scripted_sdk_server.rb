# frozen_string_literal: true

require "open_feature/sdk/isolated"
require_relative "../../../configdirector-server-sdk/spec/support/recording_logger"
require_relative "../../../configdirector-server-sdk/spec/support/scripted_sdk_server"
require_relative "../../../configdirector-server-sdk/spec/support/wire_payloads"

RSpec.shared_context "with a provider over the scripted SDK server" do
  include WirePayloads

  let(:logger) { RecordingLogger.new }
  let(:sdk_server) { ScriptedSdkServer.new }
  let(:open_feature) { OpenFeature::SDK::Isolated.create_api }
  let(:threads_registering_a_provider) { [] }

  after do
    open_feature.shutdown
    sdk_server.stop
    threads_registering_a_provider.each { |thread| thread.join(10) }
  end

  def provider_connecting_to_the_sdk_server(mode: "streaming", timeout: 5, **provider_options)
    ConfigDirector::OpenFeature::ConfigDirectorProvider.new(
      "server-sdk-key",
      connection: ConfigDirector::ConnectionOptions.new(mode: mode, timeout: timeout, url: sdk_server.url),
      logger: logger, **provider_options
    )
  end

  def start_registering(provider)
    api = open_feature
    thread = Thread.new do
      api.set_provider_and_wait(provider)
      nil
    rescue OpenFeature::SDK::ProviderInitializationError => e
      e
    end
    threads_registering_a_provider << thread
    thread
  end

  def register_over_a_stream_carrying(provider, *wire_configs)
    registering = start_registering(provider)
    stream_request = sdk_server.next_stream_request
    stream_request.open_event_stream
    stream_request.send_event(full_payload_text(configs: wire_configs))
    registration_error = registering.value
    raise registration_error unless registration_error.nil?

    stream_request
  end

  def open_feature_client_serving(*wire_configs)
    register_over_a_stream_carrying(provider_connecting_to_the_sdk_server, *wire_configs)

    open_feature.build_client
  end

  def telemetry_reported_at_shutdown
    open_feature.shutdown

    sdk_server.next_telemetry_request.json.fetch("discreteEvents")
  end

  def captured_contexts_reported_at_shutdown
    telemetry_reported_at_shutdown.fetch("capturedContexts")
  end
end
