# frozen_string_literal: true

require_relative "../support/client_of_the_scripted_sdk_server"
require_relative "../support/waiting"

RSpec.describe "The server SDK key of a client" do
  include Waiting

  include_context "with a client of the scripted SDK server"

  let(:server_sdk_key) { "key-that-no-line-may-show-4f9d2c" }
  let(:payload_serving_monday) { full_payload_text(configs: [wire_config("day-of-the-week", "Monday")]) }
  let(:connection_errors) { Queue.new }

  def client_with_the_key(url: sdk_server.url, **client_options)
    client = client_connecting_to(url, server_sdk_key: server_sdk_key, **client_options)
    client.on(:connection_error) { |event| connection_errors << event }
    client
  end

  def every_line_logged
    %i[debug info warn error].flat_map { |severity| logger.messages_at(severity) }
  end

  def lines_logged_once_one_matches(pattern)
    wait_up_to(5) { every_line_logged.grep(pattern).any? }

    every_line_logged
  end

  it "is in no log line when nothing answers at the URL" do
    client = client_with_the_key(url: ScriptedSdkServer.url_nothing_listens_on, timeout: 0.3)

    client.init
    lines = lines_logged_once_one_matches(/Scheduling reconnect attempt/)

    expect(lines.grep(/Scheduling reconnect attempt/)).not_to be_empty
    expect(lines.grep(/#{server_sdk_key}/)).to be_empty
  end

  it "is in no log line, error message or inspect output when the SDK server refuses a stream and repeats the key" do
    client = client_with_the_key
    initializing = start_init_of(client)
    sdk_server.next_stream_request.answer(status: 401, body: "Unknown server SDK key #{server_sdk_key}")
    initializing.join(10)
    connection_error_event = connection_errors.pop(timeout: 5)
    error = connection_error_event.error

    expect(every_line_logged.grep(/Connection failed with status: 401/).length).to eq(1)
    expect(every_line_logged.grep(/#{server_sdk_key}/)).to be_empty
    expect([error.message, error.inspect, error.full_message, connection_error_event.inspect, client.inspect])
      .to all(satisfy { |text| !text.include?(server_sdk_key) })
  end

  it "is in no log line, error message or inspect output when the SDK server refuses a poll and repeats the key" do
    client = client_with_the_key(mode: "polling")
    initialize_with_a_first_poll_answered(
      client, status: 401, body: JSON.generate("error" => "Unknown server SDK key #{server_sdk_key}")
    )
    connection_error_event = connection_errors.pop(timeout: 5)
    error = connection_error_event.error

    expect(error.message).to include("Unknown server SDK key [the server SDK key]")
    expect(every_line_logged.grep(/#{server_sdk_key}/)).to be_empty
    expect([error.message, error.inspect, error.full_message, connection_error_event.inspect, client.inspect])
      .to all(satisfy { |text| !text.include?(server_sdk_key) })
  end

  it "is in no log line when a message of the stream is not JSON and repeats the key" do
    client = client_with_the_key
    stream_request = initialize_over_a_stream_carrying(payload_serving_monday, client)

    stream_request.send_event("#{server_sdk_key} is not a server SDK key that ConfigDirector knows")
    lines = lines_logged_once_one_matches(/Error parsing and dispatching config data update/)

    expect(lines.grep(/Error parsing and dispatching config data update/).length).to eq(1)
    expect(lines.grep(/#{server_sdk_key}/)).to be_empty
  end

  it "is in no log line when a poll is answered with a body that is not JSON and repeats the key" do
    client = client_with_the_key(mode: "polling")
    initialize_with_a_first_poll_answered(
      client, status: 200, body: "#{server_sdk_key} is not a server SDK key that ConfigDirector knows"
    )

    expect(every_line_logged.grep(/Error during polling/).length).to eq(1)
    expect(every_line_logged.grep(/#{server_sdk_key}/)).to be_empty
  end

  it "is in no log line when the SDK server refuses a telemetry report and repeats the key" do
    sdk_server.hold_telemetry_reports
    client = client_with_the_key
    initialize_over_a_stream_carrying(payload_serving_monday, client)
    client.get_value("day-of-the-week", "Sunday")
    closing = Thread.new { client.close }

    sdk_server.next_telemetry_request.answer(status: 500, body: "Unknown server SDK key #{server_sdk_key}")
    closing.join(10)

    expect(every_line_logged.grep(/The telemetry endpoint responded with status 500/).length).to eq(1)
    expect(every_line_logged.grep(/#{server_sdk_key}/)).to be_empty
  end

  it "is in no log line when a telemetry report gets no answer" do
    sdk_server.hold_telemetry_reports
    client = client_with_the_key
    initialize_over_a_stream_carrying(payload_serving_monday, client)
    client.get_value("day-of-the-week", "Sunday")
    closing = Thread.new { client.close }

    sdk_server.next_telemetry_request.drop
    closing.join(10)

    expect(every_line_logged.grep(/Error attempting to send telemetry data/).length).to eq(1)
    expect(every_line_logged.grep(/#{server_sdk_key}/)).to be_empty
  end

  it "is in the name of no thread of a streaming client" do
    client = client_with_the_key
    initialize_over_a_stream_carrying(payload_serving_monday, client)

    expect(sdk_threads_alive.map(&:name).sort).to eq(
      %w[configdirector-heartbeat configdirector-streaming configdirector-telemetry]
    )
    expect(Thread.list.map { |thread| thread.name.to_s }.grep(/#{server_sdk_key}/)).to be_empty
  end
end
