# frozen_string_literal: true

require "timeout"
require_relative "../support/client_of_the_scripted_sdk_server"
require_relative "../support/elapsed_seconds"

RSpec.describe "A client shared between the application's threads and the SDK's" do
  include ElapsedSeconds

  include_context "with a client of the scripted SDK server"

  let(:payload_serving_monday) { full_payload_text(configs: [wire_config("day-of-the-week", "Monday")]) }
  let(:payload_serving_tuesday) { full_payload_text(configs: [wire_config("day-of-the-week", "Tuesday")]) }

  def day_read_from(client)
    client.get_value("day-of-the-week", "Sunday")
  end

  it "closes from inside a configs_updated handler on the streaming thread, and no SDK thread is left" do
    client, stream_request = streaming_client_initialized_with(payload_serving_monday)
    closed_by_the_handler = Queue.new
    client.on(:configs_updated) do
      client.close
      closed_by_the_handler << client.closed?
    end

    stream_request.send_event(payload_serving_tuesday)
    closed = closed_by_the_handler.pop(timeout: 5)
    wait_until_no_sdk_thread_is_alive

    expect(closed).to be(true)
    expect(sdk_threads_alive).to be_empty
    expect(logger.messages_at(:error)).to be_empty
  end

  it "closes from inside a watch on the streaming thread, and no SDK thread is left" do
    client, stream_request = streaming_client_initialized_with(payload_serving_monday)
    days_watched = Queue.new
    client.watch("day-of-the-week", "Sunday") do |day|
      client.close
      days_watched << day
    end

    stream_request.send_event(payload_serving_tuesday)
    day_watched = days_watched.pop(timeout: 5)
    wait_until_no_sdk_thread_is_alive

    expect(day_watched).to eq("Tuesday")
    expect(sdk_threads_alive).to be_empty
  end

  it "registers and removes watches and handlers from inside a configs_updated handler" do
    client, stream_request = streaming_client_initialized_with(payload_serving_monday)
    days_watched = Queue.new
    updates = Queue.new
    client.on(:configs_updated) do |update|
      client.unwatch("day-of-the-week")
      client.watch("day-of-the-week", "Sunday") { |day| days_watched << day }
      client.off(:config_evaluated)
      client.on(:config_evaluated) { |_event| nil }
      updates << update
    end

    stream_request.send_event(payload_serving_tuesday)
    updates.pop(timeout: 5)
    stream_request.send_event(payload_serving_monday)
    updates.pop(timeout: 5)

    expect([days_watched.pop(timeout: 5), days_watched.pop(timeout: 5)]).to eq(%w[Tuesday Monday])
    expect(logger.messages_at(:error)).to be_empty
  end

  it "returns from a close called while a handler runs on the streaming thread, once the handler ends" do
    client, stream_request = streaming_client_initialized_with(payload_serving_monday)
    handler_started = Queue.new
    handler_may_end = Queue.new
    client.on(:configs_updated) do
      handler_started << true
      handler_may_end.pop
    end
    stream_request.send_event(payload_serving_tuesday)
    handler_started.pop(timeout: 5)

    closing = Thread.new { seconds_taken { client.close } }
    sleep(0.2)
    handler_may_end << true
    seconds_close_took = closing.value
    wait_until_no_sdk_thread_is_alive

    expect(seconds_close_took).to be_between(0.15, 3)
    expect(sdk_threads_alive).to be_empty
  end

  it "returns the served value or the in-code default value to 16 threads that read while the client is closed" do
    client, = streaming_client_initialized_with(payload_serving_monday)
    keep_reading = true
    readers = Array.new(16) do
      Thread.new do
        days_read = []
        days_read << day_read_from(client) while keep_reading
        days_read << day_read_from(client)
      end
    end
    sleep(0.05)

    client.close
    keep_reading = false
    days_read_by_each_reader = Timeout.timeout(10) { readers.map(&:value) }

    expect(days_read_by_each_reader.flatten.uniq).to contain_exactly("Monday", "Sunday")
    expect(days_read_by_each_reader.map(&:last).uniq).to eq(["Sunday"])
  end

  it "returns from an init and a close that two threads call at the same time, closed and with no SDK thread left" do
    clients = Array.new(20) { client_connecting_to(sdk_server.url, timeout: 0.2) }

    clients.each do |client|
      initializing = Thread.new do
        client.init
      rescue ConfigDirector::ConfigDirectorValidationError
        :closed_before_init
      end
      closing = Thread.new { client.close }
      [initializing, closing].each { |thread| thread.join(10) }
    end
    wait_until_no_sdk_thread_is_alive

    expect(clients.map(&:closed?).uniq).to eq([true])
    expect(sdk_threads_alive).to be_empty
  end

  it "leaves no SDK thread after close, following a stream and a telemetry report on its schedule" do
    client, = streaming_client_initialized_with(payload_serving_monday)
    day_read_from(client)
    sdk_server.next_telemetry_request(within: 10)

    client.close
    wait_until_no_sdk_thread_is_alive

    expect(sdk_threads_alive).to be_empty
  end

  it "leaves no SDK thread after close, following a first poll and the report that close sends" do
    client = polling_client_initialized_with(payload_serving_monday)
    day_read_from(client)
    sdk_threads_before_close = sdk_threads_alive.map(&:name).sort

    client.close
    wait_until_no_sdk_thread_is_alive

    expect(sdk_threads_before_close).to eq(%w[configdirector-polling configdirector-telemetry])
    expect(sdk_server.next_telemetry_request(within: 0).json.fetch("aggregatedEvents").fetch("evaluatedConfig").length)
      .to eq(1)
    expect(sdk_threads_alive).to be_empty
  end
end
