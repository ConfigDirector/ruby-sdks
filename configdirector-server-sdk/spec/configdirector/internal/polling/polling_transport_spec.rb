# frozen_string_literal: true

require "rbconfig"
require "time"
require_relative "../../../support/elapsed_seconds"
require_relative "../../../support/recording_logger"
require_relative "../../../support/scripted_sdk_server"
require_relative "../../../support/sdk_threads"
require_relative "../../../support/spawned_process"

RSpec.describe ConfigDirector::Internal::Polling::PollingTransport do
  include ElapsedSeconds
  include SdkThreads
  include SpawnedProcess

  let(:logger) { RecordingLogger.new }
  let(:sdk_server) { ScriptedSdkServer.new }
  let(:payloads_delivered) { Queue.new }
  let(:threads_that_delivered) { Queue.new }
  let(:unrecoverable_errors) { Queue.new }
  let(:threads_that_reported_an_unrecoverable_error) { Queue.new }
  let(:pauses_before_the_next_poll) { Queue.new }
  let(:timing_recording_its_pauses) do
    ConfigDirector::Internal::Polling::PollTiming.on_the_clock_of_the_process(
      seconds_between_polls: 60, seconds_a_poll_may_take: 5
    ).with(pause_before_the_next_poll: ->(seconds) { pauses_before_the_next_poll << seconds })
  end
  let(:pause_until_closed) do
    lambda do |seconds|
      pauses_before_the_next_poll << seconds
      sleep(60)
    end
  end
  let(:report_unrecoverable_error) do
    lambda do |error|
      threads_that_reported_an_unrecoverable_error << Thread.current
      unrecoverable_errors << error
    end
  end
  let(:deliver_payload_text) do
    lambda do |payload_text|
      threads_that_delivered << Thread.current
      payloads_delivered << payload_text
    end
  end
  let(:transports_opened) { [] }
  let(:threads_opening_a_transport) { [] }

  after do
    transports_opened.each(&:close)
    sdk_server.stop
    threads_opening_a_transport.each { |thread| thread.join(10) }
  end

  def transport_to(
    url, metadata: ConfigDirector::Metadata.new, server_sdk_key: "server-sdk-key", **timing_changes
  )
    transport = described_class.new(
      endpoint: ConfigDirector::Internal::Polling::PollingEndpoint.new(
        url: url, server_sdk_key: server_sdk_key, metadata: metadata,
        sdk_identity: ConfigDirector::Internal::Identity::SdkIdentity.of_the_server_sdk
      ),
      timing: timing_recording_its_pauses.with(**timing_changes), logger: logger
    )
    transports_opened << transport
    transport
  end

  def start_opening(transport, &delivery_when_not_recorded)
    delivery = delivery_when_not_recorded || deliver_payload_text
    thread = Thread.new { transport.open(report_unrecoverable_error: report_unrecoverable_error, &delivery) }
    threads_opening_a_transport << thread
    thread
  end

  def start_opening_a_new_transport(url: sdk_server.url, **transport_options)
    start_opening(transport_to(url, **transport_options))
  end

  def answer_the_first_poll_of_a_new_transport(status: 200, headers: {}, body: "", **transport_options)
    opening = start_opening_a_new_transport(**transport_options)
    first_request = sdk_server.next_poll_request
    first_request.answer(status: status, headers: headers, body: body)
    opening.join(5)
    first_request
  end

  def restart_in_a_forked_process(transport)
    transport.restart_in_a_forked_process(report_unrecoverable_error: report_unrecoverable_error, &deliver_payload_text)
  end

  def next_pauses_before_the_next_poll(count)
    Array.new(count) { pauses_before_the_next_poll.pop(timeout: 5) }
  end

  def next_payloads_delivered(count)
    Array.new(count) { payloads_delivered.pop(timeout: 5) }
  end

  def mebibytes_of_padding(count)
    Array.new(count) { "x" * 1_048_576 }
  end

  def json_object_of_bytes(bytes)
    bytes_around_the_padding = '{"padding":""}'.bytesize

    %({"padding":"#{"x" * (bytes - bytes_around_the_padding)}"})
  end

  it "delivers the payload of the first poll on the thread that opens it, before open returns" do
    opening = start_opening_a_new_transport

    sdk_server.next_poll_request.answer(status: 200, body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')
    opening.join(5)

    expect(payloads_delivered.pop(timeout: 0)).to eq('{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')
    expect(threads_that_delivered.pop(timeout: 0)).to equal(opening)
  end

  it "polls again one polling interval after the first poll and delivers the payload" do
    answer_the_first_poll_of_a_new_transport(
      body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{"first":{}}}', seconds_between_polls: 90
    )

    sdk_server.next_poll_request.answer(
      status: 200, body: '{"timestamp":"2026-11-14T10:01:30.000Z","configs":{"second":{}}}'
    )

    expect(next_payloads_delivered(2)).to eq(
      [
        '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{"first":{}}}',
        '{"timestamp":"2026-11-14T10:01:30.000Z","configs":{"second":{}}}'
      ]
    )
    expect(next_pauses_before_the_next_poll(2)).to eq([90, 90])
  end

  it "delivers the payloads after the first on a thread named after what it does" do
    answer_the_first_poll_of_a_new_transport(body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')

    sdk_server.next_poll_request.answer(status: 200, body: '{"timestamp":"2026-11-14T10:01:00.000Z","configs":{}}')
    next_payloads_delivered(2)
    threads_that_delivered.pop(timeout: 0)

    expect(threads_that_delivered.pop(timeout: 0).name).to eq("configdirector-polling")
  end

  it "sends the timestamp of the last payload and the same session ID on the next poll" do
    first_request = answer_the_first_poll_of_a_new_transport(
      body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}'
    )

    second_request = sdk_server.next_poll_request

    expect(second_request.json).to eq(
      "serverSdkKey" => "server-sdk-key",
      "sessionId" => first_request.json["sessionId"],
      "metaContext" => { "sdkName" => "ruby-server-sdk", "sdkVersion" => ConfigDirector::VERSION },
      "lastUpdateTimestamp" => "2026-11-14T10:00:00.000Z"
    )
  end

  it "sends the timestamp of the newest payload once a later poll delivered one" do
    answer_the_first_poll_of_a_new_transport(body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')
    sdk_server.next_poll_request.answer(status: 200, body: '{"timestamp":"2026-11-14T10:01:00.000Z","configs":{}}')

    third_request = sdk_server.next_poll_request

    expect(third_request.json["lastUpdateTimestamp"]).to eq("2026-11-14T10:01:00.000Z")
  end

  it "delivers nothing after a 204 and sends the previous timestamp again on the poll after it" do
    answer_the_first_poll_of_a_new_transport(body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')

    sdk_server.next_poll_request.answer(status: 204)
    third_request = sdk_server.next_poll_request

    expect(third_request.json["lastUpdateTimestamp"]).to eq("2026-11-14T10:00:00.000Z")
    expect(next_payloads_delivered(1)).to eq(['{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}'])
    expect(payloads_delivered).to be_empty
    expect(next_pauses_before_the_next_poll(2)).to eq([60, 60])
    expect(logger.messages_at(:info) + logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "delivers nothing after a 202, as after a 204" do
    answer_the_first_poll_of_a_new_transport(body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')

    sdk_server.next_poll_request.answer(status: 202, body: '{"timestamp":"2026-11-14T10:01:00.000Z","configs":{}}')
    third_request = sdk_server.next_poll_request

    expect(third_request.json["lastUpdateTimestamp"]).to eq("2026-11-14T10:00:00.000Z")
    expect(next_payloads_delivered(1)).to eq(['{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}'])
    expect(payloads_delivered).to be_empty
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "keeps sending the last timestamp after a payload that has none" do
    answer_the_first_poll_of_a_new_transport(body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')
    sdk_server.next_poll_request.answer(status: 200, body: '{"configs":{"second":{}}}')

    third_request = sdk_server.next_poll_request

    expect(third_request.json["lastUpdateTimestamp"]).to eq("2026-11-14T10:00:00.000Z")
    expect(next_payloads_delivered(2).last).to eq('{"configs":{"second":{}}}')
  end

  it "sends no timestamp after a payload whose timestamp is not text" do
    answer_the_first_poll_of_a_new_transport(body: '{"timestamp":1794650400000,"configs":{}}')

    second_request = sdk_server.next_poll_request

    expect(second_request.json).not_to have_key("lastUpdateTimestamp")
    expect(next_payloads_delivered(1)).to eq(['{"timestamp":1794650400000,"configs":{}}'])
  end

  it "delivers a payload that repeats a key" do
    answer_the_first_poll_of_a_new_transport(
      body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{},"configs":{}}'
    )

    expect(payloads_delivered.pop(timeout: 0)).to eq(
      '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{},"configs":{}}'
    )
    expect(logger.messages_at(:error)).to be_empty
  end

  it "waits out the polling interval before the next poll when it is given no pause of its own" do
    process_timing = ConfigDirector::Internal::Polling::PollTiming.on_the_clock_of_the_process(
      seconds_between_polls: 0.5, seconds_a_poll_may_take: 5
    )
    opening = start_opening_a_new_transport(**process_timing.to_h)
    sdk_server.next_poll_request.answer(status: 204)
    opening.join(5)

    seconds = seconds_taken { sdk_server.next_poll_request }

    expect(seconds).to be_between(0.45, 3)
  end

  it "sends a poll the SDK server closed without answering once more at once, and logs nothing above debug level" do
    opening = start_opening_a_new_transport

    first_request = sdk_server.next_poll_request
    first_request.drop
    second_request = sdk_server.next_poll_request
    second_request.answer(status: 200, body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')
    opening.join(5)

    expect(payloads_delivered.pop(timeout: 0)).to eq('{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')
    expect(second_request.json).to eq(first_request.json)
    expect(pauses_before_the_next_poll.pop(timeout: 5)).to eq(60)
    expect(logger.messages_at(:debug)).to eq(["[PollingTransport] The poll got no answer and is sent again at once"])
    expect(logger.messages_at(:info) + logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "sends a poll whose answer was cut off in its body once more at once" do
    opening = start_opening_a_new_transport

    sdk_server.next_poll_request.answer_with_a_body_cut_off(
      status: 200, body_sent: '{"timestamp":"2026-11-14T10:00:00.000Z",', content_length: 53
    )
    sdk_server.next_poll_request.answer(status: 200, body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')
    opening.join(5)

    expect(payloads_delivered.pop(timeout: 0)).to eq('{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')
    expect(payloads_delivered).to be_empty
    expect(logger.messages_at(:info) + logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "sends the retry of a later poll with the timestamp that poll carried" do
    answer_the_first_poll_of_a_new_transport(body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')

    second_request = sdk_server.next_poll_request
    second_request.drop
    retry_of_the_second_request = sdk_server.next_poll_request

    expect(retry_of_the_second_request.json).to eq(second_request.json)
    expect(retry_of_the_second_request.json["lastUpdateTimestamp"]).to eq("2026-11-14T10:00:00.000Z")
  end

  it "sends two requests and logs one error per interval to an SDK server that closes every connection" do
    opening = start_opening_a_new_transport(seconds_a_poll_may_take: 30)

    2.times { sdk_server.next_poll_request.drop }
    opening.join(5)
    pause_after_the_first_poll = pauses_before_the_next_poll.pop(timeout: 5)
    errors_after_the_first_poll = logger.messages_at(:error)
    2.times { sdk_server.next_poll_request.drop }
    pause_after_the_second_poll = pauses_before_the_next_poll.pop(timeout: 5)
    third_poll_request = sdk_server.next_poll_request

    expect([pause_after_the_first_poll, pause_after_the_second_poll]).to eq([60, 60])
    expect(errors_after_the_first_poll.length).to eq(1)
    expect(logger.messages_at(:error).length).to eq(2)
    expect(logger.messages_at(:error)).to all(
      start_with("[PollingTransport] Error during polling: Connection failed with error: ")
    )
    expect(third_poll_request.json["serverSdkKey"]).to eq("server-sdk-key")
    expect(pauses_before_the_next_poll).to be_empty
    expect(unrecoverable_errors).to be_empty
    expect(payloads_delivered).to be_empty
  end

  it "logs one error per poll and keeps polling when nothing listens at the URL" do
    opening = start_opening_a_new_transport(
      url: ScriptedSdkServer.url_nothing_listens_on, pause_before_the_next_poll: pause_until_closed
    )

    opening.join(5)

    expect(pauses_before_the_next_poll.pop(timeout: 5)).to eq(60)
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with(
      "[PollingTransport] Error during polling: Connection failed with error: "
    )
    expect(unrecoverable_errors).to be_empty
  end

  it "gives a poll and its one retry the time a poll may take together" do
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    opening = start_opening_a_new_transport(seconds_a_poll_may_take: 1.0)
    first_request = sdk_server.next_poll_request
    sleep(0.6)

    first_request.drop
    sdk_server.next_poll_request
    opening.join(5)
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    expect(seconds).to be_between(0.9, 1.4)
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with(
      "[PollingTransport] Error during polling: Connection failed with error: "
    )
  end

  it "gives up on an answer whose body does not arrive in what is left of the time a poll may take" do
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    opening = start_opening_a_new_transport(seconds_a_poll_may_take: 1.0)
    first_request = sdk_server.next_poll_request
    sleep(0.6)

    first_request.answer_with_a_body_that_never_arrives(status: 200, content_length: 53)
    opening.join(5)
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    expect(seconds).to be_between(0.9, 1.4)
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with(
      "[PollingTransport] Error during polling: Connection failed with error: "
    )
    expect(logger.messages_at(:debug)).to be_empty
  end

  it "sends one request and logs one error per interval after a 503" do
    answer_the_first_poll_of_a_new_transport(status: 503)
    errors_after_the_first_poll = logger.messages_at(:error)

    sdk_server.next_poll_request.answer(status: 503)
    sdk_server.next_poll_request

    expect(next_pauses_before_the_next_poll(2)).to eq([60, 60])
    expect(pauses_before_the_next_poll).to be_empty
    expect(errors_after_the_first_poll).to eq(
      ["[PollingTransport] Error during polling: Connection failed with status: 503"]
    )
    expect(logger.messages_at(:error)).to eq(
      ["[PollingTransport] Error during polling: Connection failed with status: 503"] * 2
    )
    expect(unrecoverable_errors).to be_empty
  end

  it "sends one request and logs one error per interval when the SDK server does not answer in time" do
    opening = start_opening_a_new_transport(seconds_a_poll_may_take: 0.3)
    sdk_server.next_poll_request
    opening.join(5)
    errors_after_the_first_poll = logger.messages_at(:error)

    sdk_server.next_poll_request
    pauses = next_pauses_before_the_next_poll(2)
    sdk_server.next_poll_request
    transports_opened.each(&:close)

    expect(pauses).to eq([60, 60])
    expect(sdk_server.receives_a_request_to?("/server/polling/v1", within: 0)).to be(false)
    expect(errors_after_the_first_poll.length).to eq(1)
    expect(logger.messages_at(:error).length).to eq(2)
    expect(logger.messages_at(:error)).to all(
      start_with("[PollingTransport] Error during polling: Connection failed with error: ")
    )
    expect(logger.messages_at(:debug)).to be_empty
  end

  it "counts a connection that does not open within the time a poll may take as a poll that ran out of time",
     unless: Gem.win_platform? do
    opening = start_opening_a_new_transport(
      url: "http://10.255.255.1:81", seconds_a_poll_may_take: 0.3, pause_before_the_next_poll: pause_until_closed
    )

    opening.join(5)

    expect(pauses_before_the_next_poll.pop(timeout: 5)).to eq(60)
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with(
      "[PollingTransport] Error during polling: Connection failed with error: "
    )
    expect(logger.messages_at(:debug)).to be_empty
  end

  it "gives up on an answer that is still arriving when the time a poll may take has passed" do
    opening = start_opening_a_new_transport(seconds_a_poll_may_take: 0.5)

    how_far_the_answer_was_read = sdk_server.next_poll_request.answer_in_pieces(
      status: 200, pieces: ['{"padding":"', *Array.new(38, "x"), '"}'], seconds_between_pieces: 0.05
    )
    opening.join(5)

    expect(how_far_the_answer_was_read).to eq(:cut_off_by_the_client)
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with(
      "[PollingTransport] Error during polling: Connection failed with error: "
    )
    expect(logger.messages_at(:debug)).to be_empty
    expect(payloads_delivered).to be_empty
  end

  it "gives up on an answer whose last part arrives after the time a poll may take has passed" do
    clock_is_past_the_deadline = false
    opening = start_opening_a_new_transport(
      monotonic_seconds: lambda do
        Process.clock_gettime(Process::CLOCK_MONOTONIC) + (clock_is_past_the_deadline ? 3600 : 0)
      end
    )

    sdk_server.next_poll_request.answer_in_pieces(status: 200, pieces: ['{"configs":', "{}}"]) do
      clock_is_past_the_deadline = true
    end
    opening.join(5)

    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with(
      "[PollingTransport] Error during polling: Connection failed with error: "
    )
    expect(logger.messages_at(:debug)).to be_empty
    expect(payloads_delivered).to be_empty
  end

  it "stops reading an answer once it is over 32 MiB" do
    opening = start_opening_a_new_transport

    how_far_the_answer_was_read = sdk_server.next_poll_request.answer_in_pieces(
      status: 200, pieces: ['{"padding":"', *mebibytes_of_padding(64), '"}']
    )
    opening.join(5)

    expect(how_far_the_answer_was_read).to eq(:cut_off_by_the_client)
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with(
      "[PollingTransport] Error during polling: Failed to parse the response from the server: "
    )
  end

  it "logs one error and polls again on the next interval when the body of a 200 is not JSON" do
    answer_the_first_poll_of_a_new_transport(body: "<html>Bad gateway</html>")

    second_request = sdk_server.next_poll_request

    expect(second_request.json).not_to have_key("lastUpdateTimestamp")
    expect(next_pauses_before_the_next_poll(1)).to eq([60])
    expect(pauses_before_the_next_poll).to be_empty
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with(
      "[PollingTransport] Error during polling: Failed to parse the response from the server: "
    )
    expect(payloads_delivered).to be_empty
  end

  it "logs one error and delivers nothing when the body of a 200 is JSON but not an object" do
    answer_the_first_poll_of_a_new_transport(body: '["2026-11-14T10:00:00.000Z"]')

    sdk_server.next_poll_request

    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with(
      "[PollingTransport] Error during polling: Failed to parse the response from the server: "
    )
    expect(payloads_delivered).to be_empty
  end

  it "delivers a payload of exactly 32 MiB" do
    answer_the_first_poll_of_a_new_transport(body: json_object_of_bytes(33_554_432))

    expect(payloads_delivered.pop(timeout: 0).bytesize).to eq(33_554_432)
    expect(logger.messages_at(:error)).to be_empty
  end

  it "logs one error and delivers nothing when the body of a 200 is one byte over 32 MiB" do
    answer_the_first_poll_of_a_new_transport(body: json_object_of_bytes(33_554_433))

    sdk_server.next_poll_request

    expect(next_pauses_before_the_next_poll(1)).to eq([60])
    expect(pauses_before_the_next_poll).to be_empty
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with(
      "[PollingTransport] Error during polling: Failed to parse the response from the server: "
    )
    expect(payloads_delivered).to be_empty
  end

  it "delivers a byte that is not UTF-8 as U+FFFD" do
    answer_the_first_poll_of_a_new_transport(
      body: "{\"timestamp\":\"2026-11-14T10:00:00.000Z\",\"configs\":{\"greeting\":\"caf\xE9\"}}".b
    )

    payload_text = payloads_delivered.pop(timeout: 0)

    expect(payload_text).to eq(%({"timestamp":"2026-11-14T10:00:00.000Z","configs":{"greeting":"caf\uFFFD"}}))
    expect(payload_text.encoding).to eq(Encoding::UTF_8)
  end

  it "counts a redirect as a failed poll and does not follow it" do
    answer_the_first_poll_of_a_new_transport(status: 307, headers: { "Location" => "#{sdk_server.url}/elsewhere" })

    second_request = sdk_server.next_poll_request

    expect(second_request.json["serverSdkKey"]).to eq("server-sdk-key")
    expect(logger.messages_at(:error)).to eq(
      ["[PollingTransport] Error during polling: Connection failed with status: 307"]
    )
    expect(sdk_server.receives_a_request_to?("/elsewhere", within: 0)).to be(false)
  end

  it "logs one error, keeps polling and sends the earlier timestamp again when the code a payload is delivered " \
     "to raises" do
    opening = start_opening(transport_to(sdk_server.url)) do |payload_text|
      raise ArgumentError, "not a payload" if payload_text.include?("unusable")

      payloads_delivered << payload_text
    end
    sdk_server.next_poll_request.answer(status: 200, body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')
    opening.join(5)

    sdk_server.next_poll_request.answer(
      status: 200, body: '{"timestamp":"2026-11-14T10:01:00.000Z","configs":"unusable"}'
    )
    third_request = sdk_server.next_poll_request

    expect(third_request.json["lastUpdateTimestamp"]).to eq("2026-11-14T10:00:00.000Z")
    expect(next_pauses_before_the_next_poll(2)).to eq([60, 60])
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with(
      "[PollingTransport] Error during polling: Failed to parse the response from the server: "
    )
  end

  it "waits 120 seconds after a 429 that names 120 seconds in Retry-After, when the polling interval is 60" do
    answer_the_first_poll_of_a_new_transport(status: 429, headers: { "Retry-After" => "120" })

    sdk_server.next_poll_request

    expect(next_pauses_before_the_next_poll(1)).to eq([120])
    expect(pauses_before_the_next_poll).to be_empty
    expect(logger.messages_at(:error)).to eq(
      ["[PollingTransport] Error during polling: Connection failed with status: 429"]
    )
    expect(unrecoverable_errors).to be_empty
  end

  it "waits one hour after a 429 that names 7200 seconds in Retry-After" do
    answer_the_first_poll_of_a_new_transport(status: 429, headers: { "Retry-After" => "7200" })

    expect(next_pauses_before_the_next_poll(1)).to eq([3600])
  end

  it "waits a polling interval longer than one hour after a 429 that names a longer wait in Retry-After" do
    answer_the_first_poll_of_a_new_transport(
      status: 429, headers: { "Retry-After" => "7200" }, seconds_between_polls: 5400
    )

    expect(next_pauses_before_the_next_poll(1)).to eq([5400])
  end

  it "waits the polling interval after a 429 that names a shorter wait in Retry-After" do
    answer_the_first_poll_of_a_new_transport(status: 429, headers: { "Retry-After" => "30" })

    expect(next_pauses_before_the_next_poll(1)).to eq([60])
  end

  it "waits until the date a 429 names in Retry-After" do
    answer_the_first_poll_of_a_new_transport(status: 429, headers: { "Retry-After" => (Time.now + 120).httpdate })

    expect(next_pauses_before_the_next_poll(1).first).to be_between(110, 120)
  end

  it "waits the polling interval after a 429 without Retry-After" do
    answer_the_first_poll_of_a_new_transport(status: 429)

    expect(next_pauses_before_the_next_poll(1)).to eq([60])
    expect(unrecoverable_errors).to be_empty
  end

  it "waits the polling interval after a 429 whose Retry-After is neither seconds nor a date" do
    answer_the_first_poll_of_a_new_transport(status: 429, headers: { "Retry-After" => "soon" })

    expect(next_pauses_before_the_next_poll(1)).to eq([60])
  end

  it "waits the polling interval after a 503 whatever its Retry-After" do
    answer_the_first_poll_of_a_new_transport(status: 503, headers: { "Retry-After" => "120" })

    expect(next_pauses_before_the_next_poll(1)).to eq([60])
  end

  it "goes back to the polling interval after the poll that follows a 429" do
    answer_the_first_poll_of_a_new_transport(status: 429, headers: { "Retry-After" => "120" })

    sdk_server.next_poll_request.answer(status: 204)

    expect(next_pauses_before_the_next_poll(2)).to eq([120, 60])
  end

  it "stops for good after a 401 on the first poll, with one error log and one connection error whose status " \
     "is 401, reported on the thread that opens it" do
    opening = start_opening_a_new_transport

    sdk_server.next_poll_request.answer(status: 401, body: "Unauthorized")
    opening.join(5)
    error = unrecoverable_errors.pop(timeout: 0)

    expect(error).to be_a(ConfigDirector::ConfigDirectorConnectionError)
    expect(error.status).to eq(401)
    expect(error.message).to eq(
      "Connection failed with status: 401 (Unauthorized). " \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
    expect(threads_that_reported_an_unrecoverable_error.pop(timeout: 0)).to equal(opening)
    expect(logger.messages_at(:error)).to eq(
      ["[PollingTransport] Connection failed with status: 401 (Unauthorized). " \
       "This is an unrecoverable error, retry attempts will be ignored."]
    )
    expect(unrecoverable_errors).to be_empty
    expect(sdk_threads_alive).to be_empty
    expect(pauses_before_the_next_poll).to be_empty
    expect(sdk_server.receives_a_request_to?("/server/polling/v1", within: 0.2)).to be(false)
  end

  it "stops for good when a later poll is answered with a 403, reported on the polling thread" do
    answer_the_first_poll_of_a_new_transport(body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')

    sdk_server.next_poll_request.answer(status: 403, body: "Forbidden")
    error = unrecoverable_errors.pop(timeout: 5)
    wait_until_no_sdk_thread_is_alive

    expect(error.status).to eq(403)
    expect(error.message).to eq(
      "Connection failed with status: 403 (Forbidden). " \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
    expect(threads_that_reported_an_unrecoverable_error.pop(timeout: 0).name).to eq("configdirector-polling")
    expect(logger.messages_at(:error)).to eq(
      ["[PollingTransport] Connection failed with status: 403 (Forbidden). " \
       "This is an unrecoverable error, retry attempts will be ignored."]
    )
    expect(unrecoverable_errors).to be_empty
    expect(sdk_threads_alive).to be_empty
    expect(next_pauses_before_the_next_poll(1)).to eq([60])
    expect(pauses_before_the_next_poll).to be_empty
    expect(sdk_server.receives_a_request_to?("/server/polling/v1", within: 0.2)).to be(false)
  end

  it "leaves the parentheses out of the error of a refusal that has no body" do
    answer_the_first_poll_of_a_new_transport(status: 401)

    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      "Connection failed with status: 401. This is an unrecoverable error, retry attempts will be ignored."
    )
  end

  it "leaves the parentheses out of the error of a refusal whose body is blank" do
    answer_the_first_poll_of_a_new_transport(status: 401, body: " \r\n")

    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      "Connection failed with status: 401. This is an unrecoverable error, retry attempts will be ignored."
    )
  end

  it "leaves the space around the body of a refusal out of the error" do
    answer_the_first_poll_of_a_new_transport(status: 401, body: "  Unauthorized\n")

    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      "Connection failed with status: 401 (Unauthorized). " \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
  end

  it "replaces the server SDK key where the body of a refusal repeats it" do
    answer_the_first_poll_of_a_new_transport(
      status: 401, body: "The key server-sdk-key is unknown. Check server-sdk-key."
    )

    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      "Connection failed with status: 401 (The key [the server SDK key] is unknown. Check [the server SDK key].). " \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
    expect(logger.messages_at(:error).join).not_to include("server-sdk-key")
  end

  it "cuts the body of a refusal at 1,024 bytes" do
    answer_the_first_poll_of_a_new_transport(status: 401, body: "x" * 1_025)

    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      "Connection failed with status: 401 (#{"x" * 1_024}…). " \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
  end

  it "keeps a body of a refusal that is exactly 1,024 bytes whole" do
    answer_the_first_poll_of_a_new_transport(status: 401, body: "x" * 1_024)

    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      "Connection failed with status: 401 (#{"x" * 1_024}). " \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
  end

  it "leaves the space before the cut out of the body of a refusal" do
    answer_the_first_poll_of_a_new_transport(status: 401, body: "#{"x" * 1_020}    #{"y" * 100}")

    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      "Connection failed with status: 401 (#{"x" * 1_020}…). " \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
  end

  it "replaces a server SDK key that the body of a refusal repeats across its 1,024th byte" do
    answer_the_first_poll_of_a_new_transport(status: 401, body: "#{"x" * 1_020}server-sdk-key#{"y" * 100}")

    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      "Connection failed with status: 401 (#{"x" * 1_020}[the…). " \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
  end

  it "cuts the body of a refusal before a character that crosses its 1,024th byte" do
    answer_the_first_poll_of_a_new_transport(status: 401, body: "#{"x" * 1_023}é#{"y" * 100}")

    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      "Connection failed with status: 401 (#{"x" * 1_023}…). " \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
  end

  it "stops for good after a refusal whose body is over 32 MiB, and stops reading it there" do
    opening = start_opening_a_new_transport

    how_far_the_answer_was_read = sdk_server.next_poll_request.answer_in_pieces(
      status: 401, pieces: mebibytes_of_padding(64)
    )
    opening.join(5)

    expect(how_far_the_answer_was_read).to eq(:cut_off_by_the_client)
    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      "Connection failed with status: 401 (#{"x" * 1_024}…). " \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
    expect(sdk_threads_alive).to be_empty
  end

  it "replaces the server SDK key written as JSON in the body of a refusal" do
    answer_the_first_poll_of_a_new_transport(
      status: 401, body: '{"error":"The key server/sdk\\"key is unknown"}', server_sdk_key: 'server/sdk"key'
    )

    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      'Connection failed with status: 401 ({"error":"The key [the server SDK key] is unknown"}). ' \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
  end

  it "replaces the server SDK key written as JSON with its slashes escaped in the body of a refusal" do
    answer_the_first_poll_of_a_new_transport(
      status: 401, body: '{"error":"The key server\\/sdk\\"key is unknown"}', server_sdk_key: 'server/sdk"key'
    )

    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      'Connection failed with status: 401 ({"error":"The key [the server SDK key] is unknown"}). ' \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
  end

  it "replaces a server SDK key given with space around it where the body of a refusal repeats it without" do
    answer_the_first_poll_of_a_new_transport(
      status: 401, body: 'The key server/sdk"key is unknown', server_sdk_key: " server/sdk\"key\n"
    )

    expect(unrecoverable_errors.pop(timeout: 0).message).to eq(
      "Connection failed with status: 401 (The key [the server SDK key] is unknown). " \
      "This is an unrecoverable error, retry attempts will be ignored."
    )
  end

  it "closes within 5 seconds while it waits for the next poll and leaves no SDK thread alive" do
    answer_the_first_poll_of_a_new_transport(
      body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}', pause_before_the_next_poll: pause_until_closed
    )
    pauses_before_the_next_poll.pop(timeout: 5)

    seconds = seconds_taken { transports_opened.last.close }

    expect(seconds).to be < 5
    expect(sdk_threads_alive).to be_empty
  end

  it "closes within 5 seconds while a poll has no answer and leaves no SDK thread alive" do
    answer_the_first_poll_of_a_new_transport(
      body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}', seconds_a_poll_may_take: 30
    )
    sdk_server.next_poll_request

    seconds = seconds_taken { transports_opened.last.close }

    expect(seconds).to be < 5
    expect(sdk_threads_alive).to be_empty
  end

  it "returns from close after 5 seconds and lets the code a payload is delivered to finish" do
    delivery_released = Queue.new
    deliveries = Queue.new
    transport = transport_to(sdk_server.url)
    start_opening(transport) do |payload_text|
      next unless payload_text.include?("second")

      deliveries << :started
      delivery_released.pop
      deliveries << :finished
    end
    sdk_server.next_poll_request.answer(status: 200, body: '{"configs":{"first":{}}}')
    sdk_server.next_poll_request.answer(status: 200, body: '{"configs":{"second":{}}}')
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

  it "starts no polling thread when it is closed during the first poll" do
    opening = start_opening_a_new_transport
    first_request = sdk_server.next_poll_request

    seconds = seconds_taken { transports_opened.last.close }
    first_request.answer(status: 200, body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')
    opening.join(5)

    expect(seconds).to be < 1
    expect(sdk_threads_alive).to be_empty
    expect(pauses_before_the_next_poll).to be_empty
    expect(sdk_server.receives_a_request_to?("/server/polling/v1", within: 0.2)).to be(false)
  end

  it "stops polling when the code a payload is delivered to closes it" do
    transport = transport_to(sdk_server.url)
    start_opening(transport) do |payload_text|
      transport.close if payload_text.include?("second")
      payloads_delivered << payload_text
    end
    sdk_server.next_poll_request.answer(status: 200, body: '{"configs":{"first":{}}}')

    sdk_server.next_poll_request.answer(status: 200, body: '{"configs":{"second":{}}}')
    delivered = next_payloads_delivered(2)
    wait_until_no_sdk_thread_is_alive

    expect(delivered).to eq(['{"configs":{"first":{}}}', '{"configs":{"second":{}}}'])
    expect(sdk_threads_alive).to be_empty
    expect(sdk_server.receives_a_request_to?("/server/polling/v1", within: 0.2)).to be(false)
  end

  it "can be closed twice" do
    answer_the_first_poll_of_a_new_transport(body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')

    transports_opened.last.close
    transports_opened.last.close

    expect(sdk_threads_alive).to be_empty
  end

  it "ends a poll at its timeout when the SDK server keeps sending header lines" do
    opening = start_opening_a_new_transport(seconds_a_poll_may_take: 0.5)
    first_request = sdk_server.next_poll_request

    answering = Thread.new do
      first_request.answer_with_header_lines_until_cut_off(status: 200, seconds_between_lines: 0.05)
    end
    seconds_the_poll_took = seconds_taken { opening.join(5) }

    expect(seconds_the_poll_took).to be_between(0.4, 2)
    expect(answering.value).to eq(:cut_off_by_the_client)
    expect(logger.messages_at(:error).grep(/\A\[PollingTransport\] Error during polling: /).length).to eq(1)
  end

  it "can be closed without having been opened" do
    transport = transport_to(sdk_server.url)

    expect { transport.close }.not_to raise_error
  end

  it "returns from a restart in a forked process before its poll is answered, and delivers on its polling thread" do
    transport = transport_to(sdk_server.url)

    restart_in_a_forked_process(transport)
    sdk_server.next_poll_request.answer(status: 200, body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')

    expect(payloads_delivered.pop(timeout: 5)).to eq('{"timestamp":"2026-11-14T10:00:00.000Z","configs":{}}')
    expect(threads_that_delivered.pop(timeout: 0).name).to eq("configdirector-polling")
  end

  it "polls at once after a restart in a forked process, and again one polling interval after each poll" do
    transport = transport_to(sdk_server.url)

    restart_in_a_forked_process(transport)
    first_request = sdk_server.next_poll_request
    pauses_before_the_first_poll = pauses_before_the_next_poll.size
    first_request.answer(status: 200, body: '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{"first":{}}}')
    sdk_server.next_poll_request.answer(
      status: 200, body: '{"timestamp":"2026-11-14T10:01:00.000Z","configs":{"second":{}}}'
    )

    expect(pauses_before_the_first_poll).to eq(0)
    expect(next_payloads_delivered(2)).to eq(
      [
        '{"timestamp":"2026-11-14T10:00:00.000Z","configs":{"first":{}}}',
        '{"timestamp":"2026-11-14T10:01:00.000Z","configs":{"second":{}}}'
      ]
    )
    expect(next_pauses_before_the_next_poll(2)).to eq([60, 60])
  end

  it "stops for good when the poll of a restart in a forked process is answered with a 401" do
    transport = transport_to(sdk_server.url)

    restart_in_a_forked_process(transport)
    sdk_server.next_poll_request.answer(status: 401, body: "Unauthorized")
    error = unrecoverable_errors.pop(timeout: 5)
    wait_until_no_sdk_thread_is_alive

    expect(error.status).to eq(401)
    expect(unrecoverable_errors).to be_empty
    expect(sdk_threads_alive).to be_empty
    expect(pauses_before_the_next_poll).to be_empty
    expect(sdk_server.receives_a_request_to?("/server/polling/v1", within: 0.2)).to be(false)
  end

  it "ends a forked process when the delivery of a later poll that forked it returns", unless: Gem.win_platform? do
    transport = transport_to(sdk_server.url)
    forked_process_ids = Queue.new
    deliveries = 0
    opening = start_opening(transport) do |_payload_text|
      deliveries += 1
      forked_process_ids << fork if deliveries == 2
    end

    sdk_server.next_poll_request.answer(status: 200, body: '{"configs":{}}')
    opening.join(5)
    sdk_server.next_poll_request.answer(status: 200, body: '{"configs":{}}')
    process_id_of_the_fork = forked_process_ids.pop(timeout: 5)

    expect(exit_status_within(5, process_id_of_the_fork)&.exitstatus).to eq(0)
  end

  it "lets its process exit while its polling thread is alive" do
    process_id = Process.spawn(
      RbConfig.ruby, "-I", File.expand_path("../../../../lib", __dir__),
      File.expand_path("../../../support/process_with_a_polling_thread.rb", __dir__), sdk_server.url
    )

    sdk_server.next_poll_request(within: 30).answer(status: 200, body: '{"configs":{}}')
    exit_status = exit_status_within(30, process_id)

    expect(exit_status).not_to be_nil
    expect(exit_status.success?).to be(true)
  end

  it "polls with a JSON post that names the SDK as its user agent" do
    start_opening_a_new_transport

    poll_request = sdk_server.next_poll_request

    expect(poll_request.headers["content-type"]).to eq("application/json")
    expect(poll_request.headers["user-agent"]).to eq("ruby-server-sdk/#{ConfigDirector::VERSION}")
  end

  it "sends the server SDK key, a session ID and the SDK's name and version, and no timestamp, on the first poll" do
    start_opening_a_new_transport

    poll_request = sdk_server.next_poll_request

    expect(poll_request.json).to match(
      "serverSdkKey" => "server-sdk-key",
      "sessionId" => a_string_matching(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/),
      "metaContext" => { "sdkName" => "ruby-server-sdk", "sdkVersion" => ConfigDirector::VERSION }
    )
  end

  it "sends the application's name and version when the metadata has them" do
    start_opening_a_new_transport(
      metadata: ConfigDirector::Metadata.new(app_name: "my-awesome-app", app_version: "1.2.3")
    )

    poll_request = sdk_server.next_poll_request

    expect(poll_request.json["metaContext"]).to eq(
      "sdkName" => "ruby-server-sdk", "sdkVersion" => ConfigDirector::VERSION,
      "appName" => "my-awesome-app", "appVersion" => "1.2.3"
    )
  end

  it "polls below the path of a URL that has one and ends in a slash" do
    start_opening_a_new_transport(url: "#{sdk_server.url}/proxy/")

    poll_request = sdk_server.next_request_to("/proxy/server/polling/v1")

    expect(poll_request.json["serverSdkKey"]).to eq("server-sdk-key")
  end
end
