# frozen_string_literal: true

require_relative "recording_logger"
require_relative "scripted_sdk_server"
require_relative "sdk_threads"
require_relative "wire_payloads"

RSpec.shared_context "with a client of the scripted SDK server" do
  include SdkThreads
  include WirePayloads

  let(:logger) { RecordingLogger.new }
  let(:sdk_server) { ScriptedSdkServer.new }
  let(:clients_created) { [] }
  let(:threads_initializing_a_client) { [] }

  after do
    clients_created.each(&:close)
    sdk_server.stop
    threads_initializing_a_client.each { |thread| thread.join(10) }
  end

  def client_connecting_to(url, mode: "streaming", timeout: 5, **client_options)
    client = ConfigDirector.create_client(
      "server-sdk-key",
      connection: ConfigDirector::ConnectionOptions.new(mode: mode, timeout: timeout, url: url),
      logger: logger, **client_options
    )
    clients_created << client
    client
  end

  def start_init_of(client)
    thread = Thread.new { client.init }
    threads_initializing_a_client << thread
    thread
  end

  def streaming_client_initialized_with(first_payload_text, **client_options)
    client = client_connecting_to(sdk_server.url, **client_options)
    stream_request = initialize_over_a_stream_carrying(first_payload_text, client)

    [client, stream_request]
  end

  def initialize_over_a_stream_carrying(first_payload_text, client)
    initializing = start_init_of(client)
    stream_request = sdk_server.next_stream_request
    stream_request.open_event_stream
    stream_request.send_event(first_payload_text)
    initializing.join(10)

    stream_request
  end

  def polling_client_initialized_with(first_payload_text, **client_options)
    client = client_connecting_to(sdk_server.url, mode: "polling", **client_options)
    initialize_with_a_first_poll_answered(client, status: 200, body: first_payload_text)

    client
  end

  def initialize_with_a_first_poll_answered(client, status:, body: "")
    initializing = start_init_of(client)
    sdk_server.next_poll_request.answer(status: status, body: body)
    initializing.join(10)
  end

  def updates_received_by(client)
    updates = Queue.new
    client.on(:configs_updated) { |update| updates << update }
    updates
  end
end
