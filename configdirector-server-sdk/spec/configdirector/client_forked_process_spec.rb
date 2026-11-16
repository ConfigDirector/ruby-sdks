# frozen_string_literal: true

require "configdirector/testing"
require "rbconfig"
require "timeout"
require "tmpdir"
require_relative "../support/elapsed_seconds"
require_relative "../support/forked_process"
require_relative "../support/recording_logger_pausing_at_a_line"
require_relative "../support/recording_logger_writing_under_a_lock"
require_relative "../support/sdk_server_publishing_to_every_stream"
require_relative "../support/self_signed_certificate"
require_relative "../support/spawned_process"

RSpec.describe "A client in a forked process", unless: Gem.win_platform? do
  include ElapsedSeconds
  include SpawnedProcess
  include Waiting

  include_context "with an SDK server that publishes to every stream"

  let(:payload_serving_monday) { full_payload_text(configs: [wire_config("day-of-the-week", "Monday")]) }
  let(:payload_serving_tuesday) { full_payload_text(configs: [wire_config("day-of-the-week", "Tuesday")]) }

  def day_served_once_it_is_no_longer(day, client)
    wait_up_to(5) { client.get_value("day-of-the-week", "Sunday") != day }

    client.get_value("day-of-the-week", "Sunday")
  end

  def thread_repeating_every_millisecond
    Thread.new do
      loop do
        yield
        sleep(0.001)
      end
    end
  end

  def threads_publishing_to_and_reading_from(streams, client)
    payload_texts = [payload_serving_tuesday, payload_serving_monday]

    [
      thread_repeating_every_millisecond { streams.publish(payload_texts.rotate!.first) },
      thread_repeating_every_millisecond { client.get_value("day-of-the-week", "Sunday") }
    ]
  end

  def day_received_and_read_after_a_fork?(client, days_watched)
    days_watched.clear
    days_received_and_read = [days_watched.pop(timeout: 5), client.get_value("day-of-the-week", "Sunday")]

    (days_received_and_read - %w[Monday Tuesday]).empty?
  end

  def info_lines_once_there_are(count)
    wait_up_to(5) { logger.messages_at(:info).length >= count }

    logger.messages_at(:info)
  end

  it "serves an update published after the fork, in the parent and in the forked process" do
    streams = streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init

    forked_process = ForkedProcess.reporting { day_served_once_it_is_no_longer("Monday", client) }
    streams.publish(payload_serving_tuesday)

    expect(forked_process.report).to eq("Tuesday")
    expect(day_served_once_it_is_no_longer("Monday", client)).to eq("Tuesday")
  end

  it "opens a stream of its own in the forked process, under a session ID the parent never used" do
    streams = streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init
    updates = updates_received_by(client)

    forked_process = ForkedProcess.reporting { updates.pop(timeout: 5).keys }
    session_ids = streams.session_ids_once_there_are(2)

    expect(forked_process.report).to eq(["day-of-the-week"])
    expect(session_ids.length).to eq(2)
    expect(session_ids.uniq.length).to eq(2)
  end

  it "leaves the parent its stream, which carries the next update after the forked process has exited" do
    client, stream_of_the_parent = streaming_client_initialized_with(payload_serving_monday)
    updates = updates_received_by(client)

    forked_process = ForkedProcess.reporting do
      keys = updates.pop(timeout: 5).keys
      GC.start
      keys
    end
    stream_of_the_forked_process = sdk_server.next_stream_request
    stream_of_the_forked_process.open_event_stream
    stream_of_the_forked_process.send_event(payload_serving_monday)
    forked_process.report
    stream_of_the_parent.send_event(payload_serving_tuesday)

    expect(day_served_once_it_is_no_longer("Monday", client)).to eq("Tuesday")
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::STREAM_PATH, within: 0.2)).to be(false)
  end

  it "counts the attempts of its own connection from the first one in the forked process" do
    client = client_connecting_to(sdk_server.url, timeout: 0.05)
    client.init
    sdk_server.next_stream_request.answer(status: 429, headers: { "Retry-After" => "60" })
    info_lines_once_there_are(1)

    forked_process = ForkedProcess.reporting { info_lines_once_there_are(2) }
    sdk_server.next_stream_request.answer(status: 429, headers: { "Retry-After" => "60" })

    expect(forked_process.report).to eq(
      [
        "[StreamingTransport] Scheduling reconnect attempt #1 in 60 seconds.",
        "[StreamingTransport] Scheduling reconnect attempt #1 in 60 seconds."
      ]
    )
  end

  it "serves the values it was copied with at once, before its own connection has delivered any" do
    client, = streaming_client_initialized_with(payload_serving_monday)

    forked_process = ForkedProcess.reporting { [client.ready?, client.get_value("day-of-the-week", "Sunday")] }

    expect(forked_process.report).to eq([true, "Monday"])
  end

  it "calls a watch registered before the fork in a forked process that never calls the client" do
    streams = streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init
    days_watched = Queue.new
    client.watch("day-of-the-week", "Sunday") { |day| days_watched << day }

    forked_process = ForkedProcess.reporting { [days_watched.pop(timeout: 5), days_watched.pop(timeout: 5)] }
    streams.session_ids_once_there_are(2)
    streams.publish(payload_serving_tuesday)

    expect(forked_process.report).to eq(%w[Monday Tuesday])
  end

  it "restarts again in a forked process of the forked process" do
    streams = streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init

    forked_process = ForkedProcess.reporting do
      ForkedProcess.reporting { day_served_once_it_is_no_longer("Monday", client) }.report
    end
    session_ids = streams.session_ids_once_there_are(3)
    streams.publish(payload_serving_tuesday)

    expect(forked_process.report).to eq("Tuesday")
    expect(session_ids.uniq.length).to eq(3)
  end

  it "calls no client_ready handler again in the forked process of a client that was ready" do
    streams = streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init
    times_client_ready_was_called = Queue.new
    client.on(:client_ready) { times_client_ready_was_called << 1 }
    updates = updates_received_by(client)

    forked_process = ForkedProcess.reporting do
      2.times { updates.pop(timeout: 5) }
      [client.ready?, times_client_ready_was_called.size]
    end
    streams.session_ids_once_there_are(2)
    streams.publish(payload_serving_tuesday)

    expect(forked_process.report).to eq([true, 0])
  end

  it "becomes ready in the forked process when the first values arrive there, after an init that timed out" do
    client = client_connecting_to(sdk_server.url, timeout: 0.05)
    times_client_ready_was_called = Queue.new
    client.on(:client_ready) { times_client_ready_was_called << 1 }
    client.init
    sdk_server.next_stream_request

    forked_process = ForkedProcess.reporting do
      [client.ready?, times_client_ready_was_called.pop(timeout: 5), client.ready?]
    end
    stream_of_the_forked_process = sdk_server.next_stream_request
    stream_of_the_forked_process.open_event_stream
    stream_of_the_forked_process.send_event(payload_serving_monday)

    expect(forked_process.report).to eq([false, 1, true])
    expect(client.ready?).to be(false)
  end

  it "serves the answer to the poll it sends at the fork, in polling mode" do
    client = polling_client_initialized_with(payload_serving_monday)

    forked_process = ForkedProcess.reporting { day_served_once_it_is_no_longer("Monday", client) }
    sdk_server.next_poll_request.answer(status: 200, body: payload_serving_tuesday)

    expect(forked_process.report).to eq("Tuesday")
  end

  it "polls once at the fork, for what changed since the values it was copied with" do
    client = polling_client_initialized_with(payload_serving_monday)

    forked_process = ForkedProcess.reporting { day_served_once_it_is_no_longer("Monday", client) }
    poll_of_the_forked_process = sdk_server.next_poll_request
    poll_of_the_forked_process.answer(status: 200, body: payload_serving_tuesday)
    forked_process.report

    expect(poll_of_the_forked_process.json["lastUpdateTimestamp"]).to eq("2026-11-14T09:30:00.000Z")
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::POLLING_PATH, within: 0.2)).to be(false)
  end

  it "polls in the forked process under a session ID the parent never used" do
    client = client_connecting_to(sdk_server.url, mode: "polling")
    initializing = start_init_of(client)
    poll_of_the_parent = sdk_server.next_poll_request
    poll_of_the_parent.answer(status: 200, body: payload_serving_monday)
    initializing.join(10)

    forked_process = ForkedProcess.reporting { day_served_once_it_is_no_longer("Monday", client) }
    poll_of_the_forked_process = sdk_server.next_poll_request
    poll_of_the_forked_process.answer(status: 200, body: payload_serving_tuesday)
    forked_process.report

    expect(poll_of_the_forked_process.json["sessionId"]).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    expect(poll_of_the_forked_process.json["sessionId"]).not_to eq(poll_of_the_parent.json["sessionId"])
  end

  it "waits in an init called in the forked process for the first values of its own connection" do
    client = client_connecting_to(sdk_server.url, timeout: 30)
    start_init_of(client)
    sdk_server.next_stream_request

    forked_process = ForkedProcess.reporting do
      client.init
      client.ready?
    end
    stream_of_the_forked_process = sdk_server.next_stream_request
    stream_of_the_forked_process.open_event_stream
    stream_of_the_forked_process.send_event(payload_serving_monday)

    expect(forked_process.report).to be(true)
    expect(client.ready?).to be(false)
  end

  it "restarts every client that was initialized before the fork" do
    streams = streams_opened_with(payload_serving_monday)
    first_client = client_connecting_to(sdk_server.url)
    first_client.init
    second_client = client_connecting_to(sdk_server.url)
    second_client.init
    updates_of_the_first_client = updates_received_by(first_client)
    updates_of_the_second_client = updates_received_by(second_client)

    forked_process = ForkedProcess.reporting do
      [updates_of_the_first_client.pop(timeout: 5).keys, updates_of_the_second_client.pop(timeout: 5).keys]
    end

    expect(forked_process.report).to eq([["day-of-the-week"], ["day-of-the-week"]])
    expect(streams.session_ids.uniq.length).to eq(4)
  end

  it "restarts in a forked process that a signal handler forked" do
    streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init
    days_watched = Queue.new
    client.watch("day-of-the-week", "Sunday") { |day| days_watched << day }
    forked_processes = Queue.new
    handler_before = Signal.trap("USR1") do
      forked_processes << ForkedProcess.reporting { days_watched.pop(timeout: 5) }
    end

    Process.kill("USR1", Process.pid)
    forked_process = forked_processes.pop(timeout: 5)

    expect(forked_process.report).to eq("Monday")
  ensure
    Signal.trap("USR1", handler_before)
  end

  it "logs each failure at error level and lets the fork go on when the forked process cannot start a thread" do
    client, = streaming_client_initialized_with(payload_serving_monday)

    forked_process = Thread.new do
      ThreadGroup.new.add(Thread.current).freeze
      ForkedProcess.reporting { [Process.pid, logger.messages_at(:error), client.ready?] }
    end.value
    process_id_of_the_fork, error_lines, ready = forked_process.report

    expect(error_lines.length).to eq(2)
    expect(error_lines.first).to start_with(
      "[ConfigDirectorClient] Failed to restart telemetry in forked process #{process_id_of_the_fork}: " \
      'ThreadError: "can\'t start a new thread'
    )
    expect(error_lines.last).to start_with(
      "[ConfigDirectorClient] Failed to restart the connection in forked process #{process_id_of_the_fork}: " \
      'ThreadError: "can\'t start a new thread'
    )
    expect(ready).to be(true)
  end

  it "closes its own connection only when it is closed in the forked process" do
    client, stream_of_the_parent = streaming_client_initialized_with(payload_serving_monday)
    updates = updates_received_by(client)

    forked_process = ForkedProcess.reporting do
      updates.pop(timeout: 5)
      client.close
      wait_until_no_sdk_thread_is_alive
      [client.closed?, sdk_threads_alive.length]
    end
    stream_of_the_forked_process = sdk_server.next_stream_request
    stream_of_the_forked_process.open_event_stream
    stream_of_the_forked_process.send_event(payload_serving_monday)
    closed_and_threads_left_in_the_forked_process = forked_process.report
    stream_of_the_parent.send_event(payload_serving_tuesday)

    expect(closed_and_threads_left_in_the_forked_process).to eq([true, 0])
    expect(client.closed?).to be(false)
    expect(day_served_once_it_is_no_longer("Monday", client)).to eq("Tuesday")
  end

  it "calls the connection_error handlers in the forked process when the SDK server refuses its connection" do
    client, = streaming_client_initialized_with(payload_serving_monday)
    statuses_of_connection_errors = Queue.new
    client.on(:connection_error) { |event| statuses_of_connection_errors << event.error.status }

    forked_process = ForkedProcess.reporting { [statuses_of_connection_errors.pop(timeout: 5), client.ready?] }
    sdk_server.next_stream_request.answer(status: 401)

    expect(forked_process.report).to eq([401, true])
    expect(statuses_of_connection_errors).to be_empty
    expect(client.ready?).to be(true)
  end

  it "opens no connection in a forked process for a client that was never initialized" do
    streams = streams_opened_with(payload_serving_monday)
    initialized_client = client_connecting_to(sdk_server.url)
    initialized_client.init
    client_connecting_to(sdk_server.url)
    updates = updates_received_by(initialized_client)

    forked_process = ForkedProcess.reporting do
      keys = updates.pop(timeout: 5).keys
      sleep(0.3)
      keys
    end

    expect(forked_process.report).to eq(["day-of-the-week"])
    expect(streams.session_ids.length).to eq(2)
  end

  it "connects as usual when init is first called in the forked process" do
    client = client_connecting_to(sdk_server.url)

    forked_process = ForkedProcess.reporting do
      client.init
      client.get_value("day-of-the-week", "Sunday")
    end
    stream_of_the_forked_process = sdk_server.next_stream_request
    stream_of_the_forked_process.open_event_stream
    stream_of_the_forked_process.send_event(payload_serving_monday)

    expect(forked_process.report).to eq("Monday")
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::STREAM_PATH, within: 0.2)).to be(false)
  end

  it "opens no connection in a forked process for a client that was closed before the fork" do
    streams = streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init
    client.close

    forked_process = ForkedProcess.reporting do
      sleep(0.3)
      client.closed?
    end

    expect(forked_process.report).to be(true)
    expect(streams.session_ids.length).to eq(1)
  end

  it "does not try the server SDK key again in a forked process after the SDK server refused it" do
    client = client_connecting_to(sdk_server.url)
    initializing = start_init_of(client)
    sdk_server.next_stream_request.answer(status: 401)
    initializing.join(10)

    forked_process = ForkedProcess.reporting do
      sleep(0.3)
      client.ready?
    end

    expect(forked_process.report).to be(false)
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::STREAM_PATH, within: 0.2)).to be(false)
  end

  it "serves an offline client's values in a forked process, starting no thread there and logging nothing" do
    client = ConfigDirector.create_client(
      connection: ConfigDirector::ConnectionOptions.new(mode: "offline", values: { "max-items" => 20 }), logger: logger
    )
    clients_created << client
    client.init
    processes_that_started_a_thread = []
    thread_starts = TracePoint.new(:thread_begin) { processes_that_started_a_thread << Process.pid }

    forked_process = thread_starts.enable(target_thread: nil) do
      ForkedProcess.reporting do
        [
          client.ready?, client.get_value("max-items", 0), processes_that_started_a_thread.count(Process.pid),
          (logger.messages_at(:debug) + logger.messages_at(:error)).grep(/forked process/)
        ]
      end
    end

    expect(forked_process.report).to eq([true, 20, 0, []])
  end

  it "serves a test client's values in a forked process, starting no thread there and logging nothing" do
    test_client = ConfigDirector::Testing.create_test_client({ "max-items" => 20 }, logger: logger)
    clients_created << test_client.client
    test_client.client.init
    processes_that_started_a_thread = []
    thread_starts = TracePoint.new(:thread_begin) { processes_that_started_a_thread << Process.pid }

    forked_process = thread_starts.enable(target_thread: nil) do
      ForkedProcess.reporting do
        [
          test_client.client.ready?, test_client.client.get_value("max-items", 0),
          processes_that_started_a_thread.count(Process.pid),
          (logger.messages_at(:debug) + logger.messages_at(:error)).grep(/forked process/)
        ]
      end
    end

    expect(forked_process.report).to eq([true, 20, 0, []])
  end

  it "logs one debug line that names the forked process for a client that restarts" do
    client, = streaming_client_initialized_with(payload_serving_monday)

    forked_process = ForkedProcess.reporting do
      wait_up_to(5) { logger.messages_at(:debug).grep(/forked process/).any? }
      [Process.pid, logger.messages_at(:debug)]
    end
    process_id_of_the_fork, debug_lines = forked_process.report

    expect(debug_lines.grep(/forked process/)).to eq(
      ["[ConfigDirectorClient] Restarting the connection in forked process #{process_id_of_the_fork}"]
    )
    expect(client.ready?).to be(true)
  end

  it "logs nothing about a forked process in the parent" do
    client, = streaming_client_initialized_with(payload_serving_monday)

    ForkedProcess.reporting { client.ready? }.report

    expect((logger.messages_at(:debug) + logger.messages_at(:error)).grep(/forked process/)).to be_empty
  end

  it "returns at once from init in a forked process taken while the handlers of the first values still ran" do
    client = client_connecting_to(sdk_server.url, timeout: 3)
    handler_started = Queue.new
    handler_may_finish = Queue.new
    client.on(:client_ready) do
      handler_started << true
      handler_may_finish.pop
    end
    initializing = start_init_of(client)
    stream_of_the_parent = sdk_server.next_stream_request
    stream_of_the_parent.open_event_stream
    stream_of_the_parent.send_event(payload_serving_monday)
    handler_started.pop(timeout: 5)

    forked_process = ForkedProcess.reporting { seconds_taken { client.init } }
    seconds_init_took_in_the_forked_process = forked_process.report
    handler_may_finish << true
    initializing.join(10)

    expect(seconds_init_took_in_the_forked_process).to be < 2
  end

  it "serves an update published after Process.daemon, in the process it leaves" do
    streams = streams_opened_with(payload_serving_monday)
    report_reader, report_writer = IO.pipe
    process_id = Process.spawn(
      RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__),
      File.expand_path("../support/process_that_daemonizes_after_init.rb", __dir__), sdk_server.url,
      out: report_writer
    )
    report_writer.close

    session_ids = streams.session_ids_once_there_are(2, within: 30)
    streams.publish(payload_serving_tuesday)
    Process.wait(process_id)

    expect(Timeout.timeout(30) { report_reader.read }).to eq("Tuesday")
    expect(session_ids.uniq.length).to eq(2)
  end

  def in_code_default_values_reported_in(telemetry_request)
    telemetry_request.json.fetch("aggregatedEvents").fetch("evaluatedConfig").map do |evaluation|
      evaluation.fetch("event").fetch("defaultValue").fetch("value")
    end
  end

  def names_of_the_events_tracked_in(telemetry_request)
    telemetry_request.json.fetch("discreteEvents").fetch("trackedEvents").map do |tracked_event|
      tracked_event.fetch("name")
    end
  end

  it "reports from the forked process what was read there, and from the parent what it read before the fork" do
    streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init
    client.get_value("day-of-the-week", "read before the fork")

    forked_process = ForkedProcess.reporting do
      client.get_value("day-of-the-week", "read in the forked process")
      client.close
    end
    forked_process.report
    report_of_the_forked_process = sdk_server.next_telemetry_request
    client.close
    report_of_the_parent = sdk_server.next_telemetry_request

    expect(in_code_default_values_reported_in(report_of_the_forked_process)).to eq(["read in the forked process"])
    expect(in_code_default_values_reported_in(report_of_the_parent)).to eq(["read before the fork"])
    expect(report_of_the_forked_process.json.fetch("metaContext")).to eq(
      report_of_the_parent.json.fetch("metaContext")
    )
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 0)).to be(false)
  end

  it "reports from the forked process the events tracked there, and from the parent those it tracked before the fork" do
    streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init
    client.track("tracked-before-the-fork")

    forked_process = ForkedProcess.reporting do
      client.track("tracked-in-the-forked-process")
      client.close
    end
    forked_process.report
    report_of_the_forked_process = sdk_server.next_telemetry_request
    client.close
    report_of_the_parent = sdk_server.next_telemetry_request

    expect(names_of_the_events_tracked_in(report_of_the_forked_process)).to eq(["tracked-in-the-forked-process"])
    expect(names_of_the_events_tracked_in(report_of_the_parent)).to eq(["tracked-before-the-fork"])
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 0)).to be(false)
  end

  it "starts a telemetry thread of its own in the forked process" do
    streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init

    forked_process = ForkedProcess.reporting do
      wait_up_to(5) { sdk_threads_alive.any? { |thread| thread.name == "configdirector-telemetry" } }
      sleep(0.2)
      sdk_threads_alive.map(&:name)
    end

    expect(forked_process.report.count("configdirector-telemetry")).to eq(1)
  end

  it "sends its first report from the forked process 5 seconds after the fork" do
    streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init

    forked_process = ForkedProcess.reporting do
      client.get_value("day-of-the-week", "read in the forked process")
      seconds_taken { wait_up_to(8) { logger.messages_at(:debug).any? { |line| line.include?("[EventReporter]") } } }
    end
    seconds_before_the_report_was_sent = forked_process.report

    expect(seconds_before_the_report_was_sent).to be_between(4.5, 6.5)
    expect(in_code_default_values_reported_in(sdk_server.next_telemetry_request(within: 0))).to eq(
      ["read in the forked process"]
    )
  end

  it "starts no telemetry thread in the forked process for a client that ConfigDirector refused" do
    client = client_connecting_to(sdk_server.url)
    initializing = start_init_of(client)
    sdk_server.next_stream_request.answer(status: 401)
    initializing.join(10)

    forked_process = ForkedProcess.reporting do
      sleep(0.3)
      sdk_threads_alive.map(&:name)
    end

    expect(forked_process.report).not_to include("configdirector-telemetry")
  end

  it "starts no telemetry thread in the forked process for a client that was closed before the fork" do
    streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init
    client.close

    forked_process = ForkedProcess.reporting do
      sleep(0.3)
      sdk_threads_alive.map(&:name)
    end

    expect(forked_process.report).not_to include("configdirector-telemetry")
  end

  it "leaves the reads of a client that was never initialized to the process that made them" do
    client = client_connecting_to(sdk_server.url)
    client.get_value("day-of-the-week", "read before the fork")

    forked_process = ForkedProcess.reporting do
      client.get_value("day-of-the-week", "read in the forked process")
      client.close
    end
    forked_process.report
    report_of_the_forked_process = sdk_server.next_telemetry_request
    client.close
    report_of_the_parent = sdk_server.next_telemetry_request

    expect(in_code_default_values_reported_in(report_of_the_forked_process)).to eq(["read in the forked process"])
    expect(in_code_default_values_reported_in(report_of_the_parent)).to eq(["read before the fork"])
  end

  it "leaves a context with an invalid kind given before the fork out of the forked process's report" do
    streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init
    client.get_value("day-of-the-week", "Sunday", ConfigDirector::Context.new(kind: "Device"))

    forked_process = ForkedProcess.reporting do
      client.get_value("day-of-the-week", "Sunday", ConfigDirector::Context.new(kind: "Tenant"))
      client.close
    end
    forked_process.report
    invalid_contexts = sdk_server.next_telemetry_request.json.fetch("aggregatedEvents").fetch("invalidContext")

    expect(invalid_contexts.map { |entry| entry.fetch("event").fetch("kindSample") }).to eq(["Tenant"])
  end

  it "reports from the process Process.daemon leaves what was read before and after it" do
    streams_opened_with(payload_serving_monday)
    report_reader, report_writer = IO.pipe
    process_id = Process.spawn(
      RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__),
      File.expand_path("../support/process_that_daemonizes_with_telemetry_collected.rb", __dir__), sdk_server.url,
      out: report_writer
    )
    report_writer.close

    Process.wait(process_id)

    expect(Timeout.timeout(30) { report_reader.read }).to eq("closed")
    expect(in_code_default_values_reported_in(sdk_server.next_telemetry_request(within: 0))).to eq(
      ["read before Process.daemon", "read after Process.daemon"]
    )
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 0)).to be(false)
  end

  it "lets each of 200 forked processes read a value, receive values of its own and exit within 5 seconds, " \
     "while the parent receives values and sends telemetry reports" do
    streams = streams_opened_with(payload_serving_monday)
    client = client_connecting_to(
      sdk_server.url, telemetry: ConfigDirector::TelemetryOptions.new(flush_interval: 0.01)
    )
    client.init
    days_watched = Queue.new
    client.watch("day-of-the-week", "Sunday") { |day| days_watched << day }
    client.get_value("day-of-the-week", "Sunday")
    sdk_server.next_telemetry_request(within: 10)
    threads_keeping_the_parent_busy = threads_publishing_to_and_reading_from(streams, client)

    exit_statuses = Array.new(200) do
      exit_status_within(5, fork { exit!(day_received_and_read_after_a_fork?(client, days_watched)) })
    end
    threads_keeping_the_parent_busy.each { |thread| thread.kill.join }

    expect(exit_statuses.count { |exit_status| exit_status&.success? }).to eq(200)
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 1)).to be(true)
  end

  it "ends a forked process when the handler that forked it returns, and leaves the parent every later update" do
    streams = streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init
    report_reader, report_writer = IO.pipe
    forked_process_ids = Queue.new
    days_updated_to = Queue.new
    forked = false
    client.on(:configs_updated) do
      days_updated_to << client.get_value("day-of-the-week", "Sunday")
      next if forked

      forked = true
      process_id = fork
      day_read_in_the_handler = client.get_value("day-of-the-week", "Sunday")
      process_id.nil? ? report_writer.write(day_read_in_the_handler) : forked_process_ids << process_id
    end

    streams.publish(payload_serving_tuesday)
    process_id_of_the_fork = forked_process_ids.pop(timeout: 5)
    report_writer.close
    [payload_serving_monday, payload_serving_tuesday, payload_serving_monday].each { |text| streams.publish(text) }
    days_the_parent_was_updated_to = Array.new(4) { days_updated_to.pop(timeout: 5) }

    expect(exit_status_within(5, process_id_of_the_fork)&.exitstatus).to eq(0)
    expect(report_reader.read).to eq("Tuesday")
    expect(days_the_parent_was_updated_to).to eq(%w[Tuesday Monday Tuesday Monday])
  end

  it "sends no close notice on the parent's TLS stream from a forked process that a handler forked" do
    report = Dir.mktmpdir do |folder|
      certificate_path, key_path = SelfSignedCertificate.new.write_into(folder)
      IO.popen(
        { "SSL_CERT_FILE" => certificate_path },
        [RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__),
         File.expand_path("../support/process_forking_in_a_handler_over_tls.rb", __dir__), certificate_path, key_path],
        &:read
      )
    end

    expect(JSON.parse(report)).to eq(
      "exit_status_of_the_forked_process" => 0, "ends_of_a_stream_seen_by_the_server" => [],
      "day_served_by_the_parent" => "Wednesday"
    )
  end

  it "polls on one thread in a forked process that a handler of the first poll forked" do
    client = client_connecting_to(sdk_server.url, mode: "polling")
    process_id_of_the_parent = Process.pid
    report_reader, report_writer = IO.pipe
    forked_process_ids = Queue.new
    client.on(:client_ready) { forked_process_ids << fork }
    initializing = Thread.new do
      client.init
      next if Process.pid == process_id_of_the_parent

      wait_up_to(5) { sdk_threads_alive.one? { |thread| thread.name == "configdirector-polling" } }
      sleep(0.2)
      report_writer.write(JSON.generate(sdk_threads_alive.map(&:name).sort))
      exit!(0)
    end

    sdk_server.next_poll_request.answer(status: 200, body: payload_serving_monday)
    exit_status_within(10, forked_process_ids.pop(timeout: 5))
    report_writer.close
    initializing.join(10)

    expect(JSON.parse(report_reader.read)).to eq(%w[configdirector-polling configdirector-telemetry])
  end

  it "becomes ready in a forked process taken while another thread waited in init for a first poll" do
    client = client_connecting_to(sdk_server.url, mode: "polling", timeout: 30)
    start_init_of(client)
    poll_of_the_parent = sdk_server.next_poll_request

    forked_process = ForkedProcess.reporting do
      client.init
      [client.ready?, client.get_value("day-of-the-week", "Sunday")]
    end
    poll_of_the_forked_process = sdk_server.next_poll_request
    poll_of_the_forked_process.answer(status: 200, body: payload_serving_tuesday)
    ready_and_day_in_the_forked_process = forked_process.report
    poll_of_the_parent.answer(status: 200, body: payload_serving_monday)

    expect(ready_and_day_in_the_forked_process).to eq([true, "Tuesday"])
  end

  it "leaves no SDK thread in a forked process that closes the client as soon as it is forked" do
    streams = streams_opened_with(payload_serving_monday)
    client = client_connecting_to(sdk_server.url)
    client.init

    forked_process = ForkedProcess.reporting do
      client.close
      sleep(0.5)
      sdk_threads_alive.map(&:name)
    end
    sdk_threads_left_in_the_forked_process = forked_process.report
    streams.publish(payload_serving_tuesday)

    expect(sdk_threads_left_in_the_forked_process).to eq([])
    expect(day_served_once_it_is_no_longer("Monday", client)).to eq("Tuesday")
  end

  context "with a logger that writes each line under a lock, as Ruby's Logger does" do
    let(:logger) { RecordingLoggerWritingUnderALock.new }

    it "restarts in a process forked by a signal handler while the forking thread held a lock the restart takes" do
      streams_opened_with(payload_serving_monday)
      client = client_connecting_to(sdk_server.url)
      client.init
      days_watched = Queue.new
      client.watch("day-of-the-week", "Sunday") { |day| days_watched << day }
      process_id_of_the_parent = Process.pid
      report_reader, report_writer = IO.pipe
      forked_process_ids = Queue.new
      handler_before = Signal.trap("USR1") { forked_process_ids << fork }
      logger.send_once_while_the_lock_is_held("USR1")

      client.get_value("day-of-the-week", "Sunday")
      unless Process.pid == process_id_of_the_parent
        report_writer.write(days_watched.pop(timeout: 5).to_s)
        exit!(0)
      end
      exit_status_within(10, forked_process_ids.pop(timeout: 5))
      report_writer.close

      expect(report_reader.read).to eq("Monday")
    ensure
      Signal.trap("USR1", handler_before)
    end
  end

  context "with a logger that takes its time over the line about the restart" do
    let(:logger) { RecordingLoggerPausingAtALine.new("Restarting the connection in forked process", 0.3) }

    it "leaves no SDK thread in a forked process that closes the client while its connection restarts" do
      client, = streaming_client_initialized_with(payload_serving_monday)

      forked_process = ForkedProcess.reporting do
        logger.pauses_begun.pop(timeout: 5)
        client.close
        sleep(0.5)
        sdk_threads_alive.map(&:name)
      end

      expect(forked_process.report).to eq([])
      expect(client.closed?).to be(false)
    end

    it "returns from an init in a forked process once the restart has left the first values to the parent" do
      client = client_connecting_to(sdk_server.url, timeout: 5)
      handler_may_finish = Queue.new
      client.on(:client_ready) { handler_may_finish.pop }
      start_init_of(client)
      stream_of_the_parent = sdk_server.next_stream_request
      stream_of_the_parent.open_event_stream
      stream_of_the_parent.send_event(payload_serving_monday)
      wait_up_to(5) { client.ready? }

      seconds_init_took_in_the_forked_process = ForkedProcess.reporting { seconds_taken { client.init } }.report
      handler_may_finish << true

      expect(seconds_init_took_in_the_forked_process).to be_between(0.2, 3)
    end
  end

  context "with a logger that fails on every line about the forked process" do
    let(:logger) do
      Class.new(RecordingLogger) do
        def debug(message)
          raise IOError, "the log is closed" if message.include?("forked process")

          super
        end

        def error(message)
          raise IOError, "the log is closed" if message.include?("forked process")

          super
        end
      end.new
    end

    it "lets the fork go on" do
      client, = streaming_client_initialized_with(payload_serving_monday)

      forked_process = ForkedProcess.reporting { client.get_value("day-of-the-week", "Sunday") }

      expect(forked_process.report).to eq("Monday")
    end
  end
end

RSpec.describe "A client and the methods of Process" do
  it "leaves what Process says it responds to as it was before the first init" do
    report = JSON.parse(
      IO.popen(
        [RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__),
         File.expand_path("../support/process_reporting_what_process_responds_to.rb", __dir__)], &:read
      )
    )

    expect(report.fetch("after_the_first_init")).to eq(report.fetch("before_the_first_init"))
  end
end
