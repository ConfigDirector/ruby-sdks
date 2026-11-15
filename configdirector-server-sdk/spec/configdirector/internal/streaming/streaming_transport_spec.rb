# frozen_string_literal: true

require "rbconfig"
require_relative "../../../support/elapsed_seconds"
require_relative "../../../support/recording_logger"
require_relative "../../../support/scripted_sdk_server"
require_relative "../../../support/sdk_threads"
require_relative "../../../support/spawned_process"

RSpec.describe ConfigDirector::Internal::Streaming::StreamingTransport do
  include ElapsedSeconds
  include SdkThreads
  include SpawnedProcess

  let(:logger) { RecordingLogger.new }
  let(:sdk_server) { ScriptedSdkServer.new }
  let(:event_data_delivered) { Queue.new }
  let(:unrecoverable_errors) { Queue.new }
  let(:pauses_before_reconnecting) { Queue.new }
  let(:timing_without_pauses) do
    ConfigDirector::Internal::Streaming::StreamTiming.of_the_protocol.with(
      pause_before_reconnecting: ->(seconds) { pauses_before_reconnecting << seconds },
      random_fraction: -> { 0.5 }
    )
  end
  let(:timing_with_frequent_heartbeats) { timing_without_pauses.with(seconds_between_heartbeats: 0.05) }
  let(:timing_pausing_until_closed) do
    timing_without_pauses.with(
      pause_before_reconnecting: lambda do |seconds|
        pauses_before_reconnecting << seconds
        sleep(60)
      end
    )
  end
  let(:transports_opened) { [] }

  after do
    transports_opened.each(&:close)
    sdk_server.stop
  end

  def transport_to(url, metadata: ConfigDirector::Metadata.new, **timing_when_not_the_protocol)
    transport = described_class.new(
      endpoint: ConfigDirector::Internal::Streaming::StreamEndpoint.new(
        url: url, server_sdk_key: "server-sdk-key", metadata: metadata,
        sdk_identity: ConfigDirector::Internal::Identity::SdkIdentity.of_the_server_sdk
      ),
      logger: logger, **timing_when_not_the_protocol
    )
    transports_opened << transport
    transport
  end

  def open_transport(url: sdk_server.url, timing: timing_without_pauses, **transport_options)
    transport = transport_to(url, timing: timing, **transport_options)
    transport.open(report_unrecoverable_error: ->(error) { unrecoverable_errors << error }) do |event_data|
      event_data_delivered << event_data
    end
    transport
  end

  def open_stream_of_a_new_transport(**transport_options)
    open_transport(**transport_options)
    stream_request = sdk_server.next_stream_request
    stream_request.open_event_stream
    stream_request
  end

  def next_pauses_before_reconnecting(count)
    Array.new(count) { pauses_before_reconnecting.pop(timeout: 5) }
  end

  def answer_stream_requests_with_status(status, times:)
    times.times { sdk_server.next_stream_request.answer(status: status) }
  end

  it "delivers the data of the first event the stream carries" do
    stream_request = open_stream_of_a_new_transport

    stream_request.send_event('{"configs":{}}')

    expect(event_data_delivered.pop(timeout: 5)).to eq('{"configs":{}}')
  end

  it "delivers the data of each event of the stream in the order the SDK server sent them" do
    stream_request = open_stream_of_a_new_transport

    stream_request.send_event('{"configs":{"first":{}}}')
    stream_request.send_event('{"configs":{"second":{}}}')

    expect(event_data_delivered.pop(timeout: 5)).to eq('{"configs":{"first":{}}}')
    expect(event_data_delivered.pop(timeout: 5)).to eq('{"configs":{"second":{}}}')
  end

  it "asks for the stream with a JSON post that names the SDK as its user agent" do
    open_transport

    stream_request = sdk_server.next_stream_request

    expect(stream_request.headers["content-type"]).to eq("application/json")
    expect(stream_request.headers["accept"]).to eq("text/event-stream")
    expect(stream_request.headers["user-agent"]).to eq("ruby-server-sdk/#{ConfigDirector::VERSION}")
    expect(stream_request.headers).not_to have_key("last-event-id")
  end

  it "sends the server SDK key, a session ID and the SDK's name and version to open the stream" do
    open_transport

    stream_request = sdk_server.next_stream_request

    expect(stream_request.json).to match(
      "serverSdkKey" => "server-sdk-key",
      "sessionId" => a_string_matching(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/),
      "metaContext" => { "sdkName" => "ruby-server-sdk", "sdkVersion" => ConfigDirector::VERSION }
    )
  end

  it "sends the application's name and version when the metadata has them" do
    open_transport(metadata: ConfigDirector::Metadata.new(app_name: "my-awesome-app", app_version: "1.2.3"))

    stream_request = sdk_server.next_stream_request

    expect(stream_request.json["metaContext"]).to eq(
      "sdkName" => "ruby-server-sdk", "sdkVersion" => ConfigDirector::VERSION,
      "appName" => "my-awesome-app", "appVersion" => "1.2.3"
    )
  end

  it "asks for the stream below the path of a URL that has one and ends in a slash" do
    open_transport(url: "#{sdk_server.url}/proxy/")

    stream_request = sdk_server.next_request_to("/proxy/server/sse/v1")

    expect(stream_request.json["serverSdkKey"]).to eq("server-sdk-key")
  end

  it "reconnects with the last event ID and a new session ID after the SDK server drops the stream" do
    first_request = open_stream_of_a_new_transport
    first_request.send_event('{"configs":{}}', id: "event-7")
    event_data_delivered.pop(timeout: 5)

    first_request.drop
    second_request = sdk_server.next_stream_request

    expect(second_request.headers["last-event-id"]).to eq("event-7")
    expect(second_request.json["sessionId"]).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    expect(second_request.json["sessionId"]).not_to eq(first_request.json["sessionId"])
  end

  it "delivers the events of the stream that replaced a dropped one" do
    first_request = open_stream_of_a_new_transport
    first_request.drop
    second_request = sdk_server.next_stream_request
    second_request.open_event_stream

    second_request.send_event('{"configs":{"second-stream":{}}}')

    expect(event_data_delivered.pop(timeout: 5)).to eq('{"configs":{"second-stream":{}}}')
  end

  it "reconnects after the SDK server ends the stream" do
    first_request = open_stream_of_a_new_transport

    first_request.end_event_stream
    second_request = sdk_server.next_stream_request

    expect(second_request.json["sessionId"]).not_to eq(first_request.json["sessionId"])
    expect(unrecoverable_errors).to be_empty
  end

  it "sends a heartbeat for the session of the open stream on every heartbeat interval" do
    stream_request = open_stream_of_a_new_transport(timing: timing_with_frequent_heartbeats)

    first_heartbeat = sdk_server.next_heartbeat_request
    first_heartbeat.answer(status: 204)
    second_heartbeat = sdk_server.next_heartbeat_request

    expect(first_heartbeat.json).to eq(
      "serverSdkKey" => "server-sdk-key", "sessionId" => stream_request.json["sessionId"]
    )
    expect(second_heartbeat.json).to eq(
      "serverSdkKey" => "server-sdk-key", "sessionId" => stream_request.json["sessionId"]
    )
  end

  it "sends a heartbeat as a JSON post that names the SDK as its user agent" do
    open_stream_of_a_new_transport(timing: timing_with_frequent_heartbeats)

    heartbeat = sdk_server.next_heartbeat_request

    expect(heartbeat.headers["content-type"]).to eq("application/json")
    expect(heartbeat.headers["user-agent"]).to eq("ruby-server-sdk/#{ConfigDirector::VERSION}")
  end

  it "sends no heartbeat while no stream is open" do
    open_transport(timing: timing_with_frequent_heartbeats)
    sdk_server.next_stream_request

    expect(sdk_server.receives_a_request_to?("/server/heartbeat/v1", within: 0.5)).to be(false)
  end

  it "sends no heartbeat between a dropped stream and the one that replaces it" do
    first_request = open_stream_of_a_new_transport(timing: timing_with_frequent_heartbeats)
    sdk_server.next_heartbeat_request.answer(status: 204)
    first_request.drop
    sdk_server.next_stream_request
    sdk_server.request_to("/server/heartbeat/v1", within: 0.3)&.answer(status: 204)

    expect(sdk_server.receives_a_request_to?("/server/heartbeat/v1", within: 0.5)).to be(false)
  end

  it "sends heartbeats for the session of the stream that replaced a dropped one" do
    first_request = open_stream_of_a_new_transport(
      timing: timing_without_pauses.with(seconds_between_heartbeats: 0.5)
    )
    first_request.drop
    second_request = sdk_server.next_stream_request
    second_request.open_event_stream

    heartbeat = sdk_server.next_heartbeat_request

    expect(heartbeat.json["sessionId"]).to eq(second_request.json["sessionId"])
  end

  it "keeps the stream open and logs at debug level when the SDK server refuses a heartbeat" do
    stream_request = open_stream_of_a_new_transport(timing: timing_with_frequent_heartbeats)

    sdk_server.next_heartbeat_request.answer(status: 500)
    sdk_server.next_heartbeat_request
    stream_request.send_event('{"configs":{}}')

    expect(event_data_delivered.pop(timeout: 5)).to eq('{"configs":{}}')
    expect(logger.messages_at(:debug).grep(/500/).length).to eq(1)
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "keeps the stream open and logs at debug level when a heartbeat gets no answer" do
    stream_request = open_stream_of_a_new_transport(timing: timing_with_frequent_heartbeats)

    sdk_server.next_heartbeat_request.drop
    sdk_server.next_heartbeat_request
    stream_request.send_event('{"configs":{}}')

    expect(event_data_delivered.pop(timeout: 5)).to eq('{"configs":{}}')
    expect(logger.messages_at(:debug).grep(/\A\[StreamingTransport\] Heartbeat failed: /).length).to eq(1)
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "drops a stream that sends nothing for the stall timeout and reconnects" do
    first_request = open_stream_of_a_new_transport(
      timing: timing_without_pauses.with(seconds_of_silence_of_a_dropped_stream: 0.3)
    )
    first_request.send_event('{"configs":{}}', id: "event-7")

    second_request = sdk_server.next_stream_request

    expect(second_request.headers["last-event-id"]).to eq("event-7")
    expect(second_request.json["sessionId"]).not_to eq(first_request.json["sessionId"])
  end

  it "keeps a stream open while the SDK server sends nothing but keep-alive comments" do
    stream_request = open_stream_of_a_new_transport(
      timing: timing_without_pauses.with(seconds_of_silence_of_a_dropped_stream: 1.0)
    )

    8.times do
      stream_request.send_stream_text(": keep-alive\n\n")
      sleep(0.2)
    end
    stream_request.send_event('{"configs":{}}')

    expect(event_data_delivered.pop(timeout: 5)).to eq('{"configs":{}}')
    expect(sdk_server.receives_a_request_to?("/server/sse/v1", within: 0)).to be(false)
  end

  it "reconnects 2 seconds after a 429 that names 2 seconds in Retry-After" do
    open_transport

    sdk_server.next_stream_request.answer(status: 429, headers: { "Retry-After" => "2" })
    sdk_server.next_stream_request

    expect(next_pauses_before_reconnecting(1)).to eq([2])
    expect(unrecoverable_errors).to be_empty
  end

  it "backs off after a 429 without Retry-After" do
    open_transport

    sdk_server.next_stream_request.answer(status: 429)

    expect(next_pauses_before_reconnecting(1)).to eq([1.5])
  end

  it "waits at least 1 second after a 429 that names no wait in Retry-After" do
    open_transport

    sdk_server.next_stream_request.answer(status: 429, headers: { "Retry-After" => "0" })

    expect(next_pauses_before_reconnecting(1)).to eq([1])
  end

  it "waits at most 1 hour after a 429 that names a longer wait in Retry-After" do
    open_transport

    sdk_server.next_stream_request.answer(status: 429, headers: { "Retry-After" => "7200" })

    expect(next_pauses_before_reconnecting(1)).to eq([3600])
  end

  it "waits until the date a 429 names in Retry-After" do
    open_transport

    sdk_server.next_stream_request.answer(status: 429, headers: { "Retry-After" => (Time.now + 120).httpdate })

    expect(next_pauses_before_reconnecting(1).first).to be_between(110, 120)
  end

  it "backs off after a 429 whose Retry-After is neither seconds nor a date" do
    open_transport

    sdk_server.next_stream_request.answer(status: 429, headers: { "Retry-After" => "soon" })

    expect(next_pauses_before_reconnecting(1)).to eq([1.5])
  end

  it "backs off after a 503 whatever its Retry-After" do
    open_transport

    sdk_server.next_stream_request.answer(status: 503, headers: { "Retry-After" => "30" })

    expect(next_pauses_before_reconnecting(1)).to eq([1.5])
  end

  it "waits the time the stream named in its retry field after the stream drops" do
    stream_request = open_stream_of_a_new_transport
    stream_request.send_stream_text("retry: 3000\n\n")
    stream_request.send_event('{"configs":{}}')
    event_data_delivered.pop(timeout: 5)

    stream_request.drop

    expect(next_pauses_before_reconnecting(1)).to eq([3.0])
  end

  it "waits at least 1 second when the stream named a shorter time in its retry field" do
    stream_request = open_stream_of_a_new_transport
    stream_request.send_stream_text("retry: 10\n\n")
    stream_request.send_event('{"configs":{}}')
    event_data_delivered.pop(timeout: 5)

    stream_request.drop

    expect(next_pauses_before_reconnecting(1)).to eq([1])
  end

  it "waits half of 2^attempt seconds, up to 256, when the random part of the delay is nothing" do
    open_transport(timing: timing_without_pauses.with(random_fraction: -> { 0.0 }))

    answer_stream_requests_with_status(503, times: 11)

    expect(next_pauses_before_reconnecting(11)).to eq([1, 2, 4, 8, 16, 32, 64, 128, 256, 256, 256])
  end

  it "waits three quarters of 2^attempt seconds, up to 384, when the random part of the delay is half of it" do
    open_transport(timing: timing_without_pauses.with(random_fraction: -> { 0.5 }))

    answer_stream_requests_with_status(503, times: 11)

    expect(next_pauses_before_reconnecting(11)).to eq([1.5, 3, 6, 12, 24, 48, 96, 192, 384, 384, 384])
  end

  it "waits between half and the whole of 2^attempt seconds, up to 512, with the random part it draws itself" do
    protocol_timing = ConfigDirector::Internal::Streaming::StreamTiming.of_the_protocol
    open_transport(timing: timing_without_pauses.with(random_fraction: protocol_timing.random_fraction))

    answer_stream_requests_with_status(503, times: 11)

    expect(next_pauses_before_reconnecting(11)).to match(
      [
        a_value_between(1, 2), a_value_between(2, 4), a_value_between(4, 8), a_value_between(8, 16),
        a_value_between(16, 32), a_value_between(32, 64), a_value_between(64, 128), a_value_between(128, 256),
        a_value_between(256, 512), a_value_between(256, 512), a_value_between(256, 512)
      ]
    )
  end

  it "waits out the delay before it reconnects" do
    transport_to(sdk_server.url).open(report_unrecoverable_error: ->(error) { unrecoverable_errors << error }) do |data|
      event_data_delivered << data
    end
    sdk_server.next_stream_request.answer(status: 503)

    seconds = seconds_taken { sdk_server.next_stream_request }

    expect(seconds).to be_between(0.95, 5)
  end

  it "keeps the timing the protocol fixes unless it is given another" do
    protocol_timing = ConfigDirector::Internal::Streaming::StreamTiming.of_the_protocol

    expect(protocol_timing.seconds_between_heartbeats).to eq(90)
    expect(protocol_timing.seconds_of_silence_of_a_dropped_stream).to eq(45)
    expect(protocol_timing.seconds_to_open_a_stream).to eq(10)
  end

  it "counts a connection that does not open within the time to open a stream as a failed attempt",
     unless: Gem.win_platform? do
    open_transport(
      url: "http://10.255.255.1:81", timing: timing_without_pauses.with(seconds_to_open_a_stream: 0.2)
    )

    expect(next_pauses_before_reconnecting(2)).to eq([1.5, 3])
    expect(unrecoverable_errors).to be_empty
  end

  it "starts the attempt count over once a stream has opened" do
    open_transport
    answer_stream_requests_with_status(503, times: 2)
    stream_request = sdk_server.next_stream_request
    stream_request.open_event_stream

    stream_request.drop
    answer_stream_requests_with_status(503, times: 1)

    expect(next_pauses_before_reconnecting(4)).to eq([1.5, 3, 1.5, 3])
  end

  it "logs the first 5 reconnections in a row at info level and the ones after at warning level" do
    open_transport

    answer_stream_requests_with_status(503, times: 7)
    next_pauses_before_reconnecting(7)

    expect(logger.messages_at(:info).length).to eq(5)
    expect(logger.messages_at(:warn).length).to eq(2)
    expect(logger.messages_at(:info) + logger.messages_at(:warn)).to all(start_with("[StreamingTransport] "))
    expect(logger.messages_at(:error)).to be_empty
  end

  it "keeps trying to connect to an SDK server that does not answer" do
    open_transport(url: ScriptedSdkServer.url_nothing_listens_on)

    expect(next_pauses_before_reconnecting(3)).to eq([1.5, 3, 6])
    expect(unrecoverable_errors).to be_empty
    expect(logger.messages_at(:error)).to be_empty
  end

  it "counts a redirect as a failed attempt and does not follow it" do
    open_transport

    sdk_server.next_stream_request.answer(status: 307, headers: { "Location" => "#{sdk_server.url}/elsewhere" })
    second_request = sdk_server.next_stream_request

    expect(second_request.json["serverSdkKey"]).to eq("server-sdk-key")
    expect(next_pauses_before_reconnecting(1)).to eq([1.5])
  end

  it "stops for good after a 401, with one error log and one connection error whose status is 401" do
    open_transport

    sdk_server.next_stream_request.answer(status: 401)
    error = unrecoverable_errors.pop(timeout: 5)
    wait_until_no_sdk_thread_is_alive

    expect(error).to be_a(ConfigDirector::ConfigDirectorConnectionError)
    expect(error.status).to eq(401)
    expect(error.message).to eq(
      "Connection failed with status: 401. This is an unrecoverable error, will not attempt to reconnect."
    )
    expect(logger.messages_at(:error)).to eq(
      ["[StreamingTransport] Connection failed with status: 401. " \
       "This is an unrecoverable error, will not attempt to reconnect."]
    )
    expect(unrecoverable_errors).to be_empty
    expect(sdk_threads_alive).to be_empty
    expect(pauses_before_reconnecting).to be_empty
    expect(sdk_server.receives_a_request_to?("/server/sse/v1", within: 0)).to be(false)
  end

  it "stops for good when a reconnection is answered with a 403" do
    first_request = open_stream_of_a_new_transport
    first_request.drop

    sdk_server.next_stream_request.answer(status: 403)
    error = unrecoverable_errors.pop(timeout: 5)
    wait_until_no_sdk_thread_is_alive

    expect(error.status).to eq(403)
    expect(sdk_threads_alive).to be_empty
    expect(next_pauses_before_reconnecting(1)).to eq([1.5])
    expect(pauses_before_reconnecting).to be_empty
  end

  it "ends without a reconnection or an error after a 204" do
    open_transport

    sdk_server.next_stream_request.answer(status: 204)
    wait_until_no_sdk_thread_is_alive

    expect(sdk_threads_alive).to be_empty
    expect(pauses_before_reconnecting).to be_empty
    expect(unrecoverable_errors).to be_empty
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "logs one error and keeps the stream open when the code an event is delivered to raises" do
    transport_to(sdk_server.url).open(report_unrecoverable_error: ->(error) { unrecoverable_errors << error }) do |data|
      raise ArgumentError, "not a payload" if data == "not a payload"

      event_data_delivered << data
    end
    stream_request = sdk_server.next_stream_request
    stream_request.open_event_stream

    stream_request.send_event("not a payload")
    stream_request.send_event('{"configs":{}}')

    expect(event_data_delivered.pop(timeout: 5)).to eq('{"configs":{}}')
    expect(logger.messages_at(:error).length).to eq(1)
    expect(sdk_server.receives_a_request_to?("/server/sse/v1", within: 0)).to be(false)
  end

  it "drops the stream and reconnects when the SDK server sends a line longer than 1 MiB" do
    first_request = open_stream_of_a_new_transport

    first_request.send_stream_text("data: #{"x" * 1_048_577}")
    second_request = sdk_server.next_stream_request

    expect(second_request.json["sessionId"]).not_to eq(first_request.json["sessionId"])
    expect(event_data_delivered).to be_empty
  end

  it "closes within 5 seconds while a stream is open and leaves no SDK thread alive" do
    transport = open_transport
    stream_request = sdk_server.next_stream_request
    stream_request.open_event_stream
    stream_request.send_event('{"configs":{}}')
    event_data_delivered.pop(timeout: 5)

    seconds = seconds_taken { transport.close }

    expect(seconds).to be < 5
    expect(sdk_threads_alive).to be_empty
  end

  it "closes within 5 seconds while it waits to reconnect and leaves no SDK thread alive" do
    transport = open_transport(timing: timing_pausing_until_closed)
    sdk_server.next_stream_request.answer(status: 503)
    pauses_before_reconnecting.pop(timeout: 5)

    seconds = seconds_taken { transport.close }

    expect(seconds).to be < 5
    expect(sdk_threads_alive).to be_empty
  end

  it "closes within 5 seconds while the SDK server has not answered and leaves no SDK thread alive" do
    transport = open_transport
    sdk_server.next_stream_request

    seconds = seconds_taken { transport.close }

    expect(seconds).to be < 5
    expect(sdk_threads_alive).to be_empty
  end

  it "closes within 5 seconds while a heartbeat has no answer and leaves no SDK thread alive" do
    transport = open_transport(timing: timing_with_frequent_heartbeats)
    sdk_server.next_stream_request.open_event_stream
    sdk_server.next_heartbeat_request

    seconds = seconds_taken { transport.close }

    expect(seconds).to be < 5
    expect(sdk_threads_alive).to be_empty
  end

  it "returns from close after 5 seconds and lets the code an event is delivered to finish" do
    delivery_released = Queue.new
    deliveries = Queue.new
    transport = transport_to(sdk_server.url)
    transport.open(report_unrecoverable_error: ->(error) { unrecoverable_errors << error }) do |_event_data|
      deliveries << :started
      delivery_released.pop
      deliveries << :finished
    end
    stream_request = sdk_server.next_stream_request
    stream_request.open_event_stream
    stream_request.send_event('{"configs":{}}')
    deliveries.pop(timeout: 5)

    closing = Thread.new { seconds_taken { transport.close } }
    closed_in_time = closing.join(10)
    delivery_released << true
    wait_until_no_sdk_thread_is_alive

    expect(closed_in_time).not_to be_nil
    expect(closing.value).to be_between(4.9, 10)
    expect(deliveries.pop(timeout: 5)).to eq(:finished)
    expect(sdk_threads_alive).to be_empty
  end

  it "can be closed twice" do
    transport = open_transport
    sdk_server.next_stream_request

    transport.close
    transport.close

    expect(sdk_threads_alive).to be_empty
  end

  it "can be closed without having been opened" do
    transport = transport_to(sdk_server.url)

    expect { transport.close }.not_to raise_error
  end

  it "stops for good when the code an event is delivered to closes it" do
    transport = transport_to(sdk_server.url)
    transport.open(report_unrecoverable_error: ->(error) { unrecoverable_errors << error }) do |event_data|
      transport.close
      event_data_delivered << event_data
    end
    stream_request = sdk_server.next_stream_request
    stream_request.open_event_stream

    stream_request.send_stream_text(%(data: {"configs":{"first":{}}}\n\ndata: {"configs":{"second":{}}}\n\n))
    wait_until_no_sdk_thread_is_alive

    expect(sdk_threads_alive).to be_empty
    expect(event_data_delivered.pop(timeout: 5)).to eq('{"configs":{"first":{}}}')
    expect(event_data_delivered).to be_empty
    expect(pauses_before_reconnecting).to be_empty
  end

  it "lets its process exit while both of its threads are alive" do
    process_id = Process.spawn(
      RbConfig.ruby, "-I", File.expand_path("../../../../lib", __dir__),
      File.expand_path("../../../support/process_with_an_open_stream.rb", __dir__), sdk_server.url
    )
    stream_request = sdk_server.next_stream_request(within: 30)
    stream_request.open_event_stream

    stream_request.send_event('{"configs":{}}')
    exit_status = exit_status_within(30, process_id)

    expect(exit_status).not_to be_nil
    expect(exit_status.success?).to be(true)
  end

  it "names its two threads after what they do" do
    open_stream_of_a_new_transport

    expect(sdk_threads_alive.map(&:name)).to contain_exactly("configdirector-streaming", "configdirector-heartbeat")
  end
end
