# frozen_string_literal: true

require_relative "../support/client_of_the_scripted_sdk_server"
require_relative "../support/elapsed_seconds"

RSpec.describe "A client's connection to ConfigDirector" do
  include ElapsedSeconds

  include_context "with a client of the scripted SDK server"

  let(:payload_serving_monday) { full_payload_text(configs: [wire_config("day-of-the-week", "Monday")]) }
  let(:payload_serving_tuesday) { full_payload_text(configs: [wire_config("day-of-the-week", "Tuesday")]) }

  it "becomes ready and serves the values of the first payload in streaming mode" do
    client, = streaming_client_initialized_with(payload_serving_monday)

    expect(client.ready?).to be(true)
    expect(client.get_value("day-of-the-week", "Sunday")).to eq("Monday")
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "becomes ready and serves the values of the first poll in polling mode" do
    client = polling_client_initialized_with(payload_serving_monday)

    expect(client.ready?).to be(true)
    expect(client.get_value("day-of-the-week", "Sunday")).to eq("Monday")
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "asks the SDK server for nothing before init" do
    client_connecting_to(sdk_server.url)

    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::STREAM_PATH, within: 0.2)).to be(false)
  end

  it "returns from init after the timeout with one warning when the SDK server never answers" do
    client = client_connecting_to(sdk_server.url, timeout: 0.2)

    seconds = seconds_taken { client.init }

    expect(seconds).to be_between(0.2, 3)
    expect(client.ready?).to be(false)
    expect(logger.messages_at(:warn)).to eq(
      ["[ConfigDirectorClient] Timed out waiting for initialization after 0.2s. The client will continue to " \
       "retry since there were no fatal errors detected. Configs will return the in-code default value until " \
       "the connection succeeds."]
    )
    expect(logger.messages_at(:error)).to be_empty
  end

  it "returns the in-code default value after an init that timed out" do
    client = client_connecting_to(sdk_server.url, timeout: 0.05)
    client.init

    evaluation = client.evaluate("day-of-the-week", "Sunday")

    expect(evaluation.value).to eq("Sunday")
    expect(evaluation.reason).to eq("client-not-ready")
  end

  it "serves the values that arrive once the SDK server answers after init timed out" do
    client = client_connecting_to(sdk_server.url, timeout: 0.05)
    updates = updates_received_by(client)
    client.init
    stream_request = sdk_server.next_stream_request

    stream_request.open_event_stream
    stream_request.send_event(payload_serving_monday)
    updates.pop(timeout: 5)

    expect(client.ready?).to be(true)
    expect(client.get_value("day-of-the-week", "Sunday")).to eq("Monday")
  end

  it "returns from init as soon as the first payload arrives" do
    client = client_connecting_to(sdk_server.url, timeout: 30)

    seconds = seconds_taken { initialize_over_a_stream_carrying(payload_serving_monday, client) }

    expect(seconds).to be < 10
    expect(client.ready?).to be(true)
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "returns from init only after the handlers of the first payload have run" do
    client = client_connecting_to(sdk_server.url)
    handlers_that_ran = Queue.new
    client.on(:client_ready) do
      sleep(0.2)
      handlers_that_ran << :client_ready
    end

    initialize_over_a_stream_carrying(payload_serving_monday, client)

    expect(handlers_that_ran.size).to eq(1)
  end

  it "returns from init at the timeout without a warning while the handlers of the first payload still run" do
    client = client_connecting_to(sdk_server.url, timeout: 1)
    handler_may_finish = Queue.new
    client.on(:client_ready) { handler_may_finish.pop }

    seconds = seconds_taken { initialize_over_a_stream_carrying(payload_serving_monday, client) }
    handler_may_finish << true

    expect(seconds).to be_between(1, 4)
    expect(client.ready?).to be(true)
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "returns at once from an init that a configs_updated handler calls during the first payload" do
    client = client_connecting_to(sdk_server.url, timeout: 30)
    client.on(:configs_updated) { |_update| client.init }

    seconds = seconds_taken { initialize_over_a_stream_carrying(payload_serving_monday, client) }

    expect(seconds).to be < 10
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::STREAM_PATH, within: 0.2)).to be(false)
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "opens one stream however often init is called" do
    client, = streaming_client_initialized_with(payload_serving_monday)

    client.init

    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::STREAM_PATH, within: 0.2)).to be(false)
  end

  it "waits again, with another warning, when init is called again without values" do
    client = client_connecting_to(sdk_server.url, timeout: 0.05)

    client.init
    client.init

    expect(logger.messages_at(:warn).length).to eq(2)
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::STREAM_PATH, within: 5)).to be(true)
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::STREAM_PATH, within: 0.2)).to be(false)
  end

  it "serves a read from another thread while init waits for the first poll" do
    client = client_connecting_to(sdk_server.url, mode: "polling")
    initializing = start_init_of(client)
    first_poll = sdk_server.next_poll_request

    evaluation = Thread.new { client.evaluate("day-of-the-week", "Sunday") }.value
    first_poll.answer(status: 200, body: payload_serving_monday)
    initializing.join(10)

    expect(evaluation.reason).to eq("client-not-ready")
  end

  it "polls no more once it is closed while init waits for the first poll" do
    client = client_connecting_to(sdk_server.url, mode: "polling")
    initializing = start_init_of(client)
    first_poll = sdk_server.next_poll_request
    closing = Thread.new { client.close }

    first_poll.answer(status: 200, body: payload_serving_monday)
    initializing.join(10)
    closing.join(10)
    wait_until_no_sdk_thread_is_alive

    expect(client.closed?).to be(true)
    expect(client.ready?).to be(false)
    expect(sdk_threads_alive).to be_empty
  end

  it "serves the latest payload of the stream" do
    client, stream_request = streaming_client_initialized_with(payload_serving_monday)
    updates = updates_received_by(client)

    stream_request.send_event(payload_serving_tuesday)
    updates.pop(timeout: 5)

    expect(client.get_value("day-of-the-week", "Sunday")).to eq("Tuesday")
  end

  it "stops its streaming and heartbeat threads when it is closed" do
    client, = streaming_client_initialized_with(payload_serving_monday)

    client.close
    wait_until_no_sdk_thread_is_alive

    expect(sdk_threads_alive).to be_empty
  end

  it "ends a pending init without a warning when the client is closed from another thread" do
    client = client_connecting_to(sdk_server.url, timeout: 30)
    pending_init = Thread.new { seconds_taken { client.init } }
    sdk_server.next_stream_request

    client.close

    expect(pending_init.value).to be < 10
    expect(client.ready?).to be(false)
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "returns from init with one error and one connection_error when the SDK server answers a stream with 401" do
    events_of_the_hook = []
    events_of_the_handler = []
    hooks = ConfigDirector::ClientHooks.new(connection_error: ->(event) { events_of_the_hook << event })
    client = client_connecting_to(sdk_server.url, timeout: 30, hooks: hooks)
    client.on(:connection_error) { |event| events_of_the_handler << event }
    pending_init = Thread.new { seconds_taken { client.init } }

    sdk_server.next_stream_request.answer(status: 401)

    expect(pending_init.value).to be < 10
    expect(client.ready?).to be(false)
    expect(events_of_the_hook.map { |event| event.error.status }).to eq([401])
    expect(events_of_the_handler).to eq(events_of_the_hook)
    expect(events_of_the_handler.first.error).to be_a(ConfigDirector::ConfigDirectorConnectionError)
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "returns from init with one error and one connection_error when the SDK server answers the first poll with 401" do
    connection_errors = []
    client = client_connecting_to(sdk_server.url, mode: "polling", timeout: 30)
    client.on(:connection_error) { |event| connection_errors << [event.error.status, Thread.current] }
    pending_init = Thread.new { seconds_taken { client.init } }

    sdk_server.next_poll_request.answer(status: 401)

    expect(pending_init.value).to be < 10
    expect(client.ready?).to be(false)
    expect(connection_errors).to eq([[401, pending_init]])
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "returns from a later init at once, without a warning or a second stream, after the SDK server answered 401" do
    client = client_connecting_to(sdk_server.url, timeout: 30)
    initializing = start_init_of(client)
    sdk_server.next_stream_request.answer(status: 401)
    initializing.join(10)

    seconds = seconds_taken { client.init }

    expect(seconds).to be < 10
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::STREAM_PATH, within: 0.2)).to be(false)
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "keeps serving the values it has after the SDK server answers a later stream with 401" do
    client, stream_request = streaming_client_initialized_with(payload_serving_monday)
    connection_errors = Queue.new
    client.on(:connection_error) { |event| connection_errors << event }

    stream_request.end_event_stream
    sdk_server.next_stream_request(within: 10).answer(status: 401)
    connection_errors.pop(timeout: 5)

    expect(client.ready?).to be(true)
    expect(client.get_value("day-of-the-week", "Sunday")).to eq("Monday")
  end

  it "returns from init as soon as the first poll has failed, with the error of the poll and no warning" do
    client = client_connecting_to(sdk_server.url, mode: "polling", timeout: 30)
    pending_init = Thread.new { seconds_taken { client.init } }

    sdk_server.next_poll_request.answer(status: 500)

    expect(pending_init.value).to be < 10
    expect(client.ready?).to be(false)
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with("[PollingTransport] ")
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "returns from init within the timeout, with one error and no warning, when the first poll gets no answer" do
    client = client_connecting_to(sdk_server.url, mode: "polling", timeout: 0.3)

    seconds = seconds_taken { client.init }

    expect(seconds).to be_between(0.3, 3)
    expect(client.ready?).to be(false)
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "waits again, with the warning of polling mode, when init is called again after a first poll that failed" do
    client = client_connecting_to(sdk_server.url, mode: "polling", timeout: 0.2)
    initialize_with_a_first_poll_answered(client, status: 500)

    seconds = seconds_taken { client.init }

    expect(seconds).to be_between(0.2, 3)
    expect(logger.messages_at(:warn)).to eq(
      ["[ConfigDirectorClient] Timed out waiting for initialization after 0.2s. Since the client was " \
       "configured without streaming, configs may not update and always return the in-code default value."]
    )
  end

  it "waits for the timeout in all, the first poll included, when the first poll brings no values" do
    client = client_connecting_to(sdk_server.url, mode: "polling", timeout: 2)
    pending_init = Thread.new { seconds_taken { client.init } }
    first_poll = sdk_server.next_poll_request

    sleep(1.5)
    first_poll.answer(status: 204)

    expect(pending_init.value).to be_between(1.9, 3)
    expect(client.ready?).to be(false)
    expect(logger.messages_at(:warn)).to eq(
      ["[ConfigDirectorClient] Timed out waiting for initialization after 2s. Since the client was " \
       "configured without streaming, configs may not update and always return the in-code default value."]
    )
    expect(logger.messages_at(:error)).to be_empty
  end

  it "treats a first poll answered 200 without a configs object as a failed poll" do
    client = client_connecting_to(sdk_server.url, mode: "polling", timeout: 30)

    seconds = seconds_taken do
      initialize_with_a_first_poll_answered(client, status: 200, body: '{"timestamp":"2026-11-14T09:30:00.000Z"}')
    end

    expect(seconds).to be < 10
    expect(client.ready?).to be(false)
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with("[PollingTransport] Error during polling: ")
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "skips a message of the stream without a configs object with one debug line and serves the next one" do
    client = client_connecting_to(sdk_server.url)
    updates = updates_received_by(client)
    initializing = start_init_of(client)
    stream_request = sdk_server.next_stream_request
    stream_request.open_event_stream

    stream_request.send_event('{"kind":"notice"}')
    stream_request.send_event(payload_serving_monday)
    initializing.join(10)

    expect(updates.size).to eq(1)
    expect(client.get_value("day-of-the-week", "Sunday")).to eq("Monday")
    expect(logger.messages_at(:debug)).to include(
      a_string_starting_with("[StreamingTransport] Skipping a message that is not a server SDK payload: ")
    )
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "skips a message of the stream that is not a JSON object with one debug line" do
    client = client_connecting_to(sdk_server.url)
    initializing = start_init_of(client)
    stream_request = sdk_server.next_stream_request
    stream_request.open_event_stream

    stream_request.send_event('["day-of-the-week"]')
    stream_request.send_event(payload_serving_monday)
    initializing.join(10)

    expect(client.get_value("day-of-the-week", "Sunday")).to eq("Monday")
    expect(logger.messages_at(:debug)).to include(
      a_string_starting_with("[StreamingTransport] Skipping a message that is not a server SDK payload: ")
    )
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "logs one error for a message of the stream that is not JSON and serves the next one" do
    client = client_connecting_to(sdk_server.url)
    initializing = start_init_of(client)
    stream_request = sdk_server.next_stream_request
    stream_request.open_event_stream

    stream_request.send_event('{"configs":')
    stream_request.send_event(payload_serving_monday)
    initializing.join(10)

    expect(client.get_value("day-of-the-week", "Sunday")).to eq("Monday")
    expect(logger.messages_at(:error).length).to eq(1)
    expect(logger.messages_at(:error).first).to start_with("[StreamingTransport] ")
  end

  it "runs the handlers of a stream's payloads on the SDK's streaming thread" do
    client = client_connecting_to(sdk_server.url)
    names_of_delivering_threads = []
    client.on(:configs_updated) { |_update| names_of_delivering_threads << Thread.current.name }
    client.watch("day-of-the-week", "Sunday") { |_value| names_of_delivering_threads << Thread.current.name }
    client.on(:client_ready) { names_of_delivering_threads << Thread.current.name }

    initialize_over_a_stream_carrying(payload_serving_monday, client)

    expect(names_of_delivering_threads).to eq(%w[configdirector-streaming] * 3)
  end

  it "runs the handlers of the first poll's payload on the thread that called init" do
    client = client_connecting_to(sdk_server.url, mode: "polling")
    delivering_threads = []
    client.on(:configs_updated) { |_update| delivering_threads << Thread.current }
    client.watch("day-of-the-week", "Sunday") { |_value| delivering_threads << Thread.current }
    client.on(:client_ready) { delivering_threads << Thread.current }
    initializing = start_init_of(client)

    sdk_server.next_poll_request.answer(status: 200, body: payload_serving_monday)
    initializing.join(10)

    expect(delivering_threads).to eq([initializing] * 3)
  end

  it "is ready after init in offline mode without asking the SDK server for anything" do
    client = client_connecting_to(sdk_server.url, mode: "offline")

    client.init

    expect(client.ready?).to be(true)
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::STREAM_PATH, within: 0.2)).to be(false)
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::POLLING_PATH, within: 0)).to be(false)
    expect(sdk_threads_alive).to be_empty
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "returns the in-code default value of every read in offline mode" do
    client = client_connecting_to(sdk_server.url, mode: "offline")
    client.init

    evaluation = client.evaluate("day-of-the-week", "Sunday")

    expect(evaluation.value).to eq("Sunday")
    expect(evaluation.reason).to eq("config-state-missing")
    expect(client.get_all_configs).to eq({})
  end

  it "calls configs_updated with no keys and then client_ready during init in offline mode" do
    client = client_connecting_to(sdk_server.url, mode: "offline")
    deliveries = []
    client.on(:configs_updated) { |update| deliveries << update }
    client.on(:client_ready) { deliveries << :client_ready }

    client.init

    expect(deliveries).to eq([ConfigDirector::ConfigsUpdatedEvent.new(keys: [], removed_keys: []), :client_ready])
  end

  it "names the server SDK and its version to the SDK server in streaming mode" do
    client = client_connecting_to(sdk_server.url, timeout: 0.05)
    client.init

    stream_request = sdk_server.next_stream_request

    expect(stream_request.headers["user-agent"]).to eq("ruby-server-sdk/#{ConfigDirector::VERSION}")
    expect(stream_request.json["metaContext"]).to eq(
      "sdkName" => "ruby-server-sdk", "sdkVersion" => ConfigDirector::VERSION
    )
  end

  it "polls with the server SDK key and the application's name and version in polling mode" do
    client = client_connecting_to(
      sdk_server.url,
      mode: "polling", metadata: ConfigDirector::Metadata.new(app_name: "storefront", app_version: "1.4.0")
    )
    start_init_of(client)

    poll_request = sdk_server.next_poll_request
    poll_request.answer(status: 200, body: payload_serving_monday)

    expect(poll_request.json["serverSdkKey"]).to eq("server-sdk-key")
    expect(poll_request.json["metaContext"]).to eq(
      "sdkName" => "ruby-server-sdk", "sdkVersion" => ConfigDirector::VERSION, "appName" => "storefront",
      "appVersion" => "1.4.0"
    )
  end
end
