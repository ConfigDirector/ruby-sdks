# frozen_string_literal: true

require_relative "../support/recording_logger"
require_relative "../support/scripted_connection"

RSpec.describe ConfigDirector::ConfigDirectorClient do
  let(:logger) { RecordingLogger.new }

  def integer_config_serving(served_text)
    ConfigDirector::Internal::Connection::ConfigDefinition.new(
      id: "9a3e5b71-6c2d-4f08-8b1a-4d7c2e9f5a03", key: "integer-config", type: "integer",
      targeting_rules: ConfigDirector::Internal::Evaluation::TargetingRules.new(
        default_value: served_text, default_value_id: nil, default_variation_id: nil, rules: []
      ),
      variations: []
    )
  end

  def string_config_serving(served_text)
    ConfigDirector::Internal::Connection::ConfigDefinition.new(
      id: "5c8a2d94-1b7f-4e63-a0d5-9f3b6c1e7d04", key: "day-of-the-week-config", type: "string",
      targeting_rules: ConfigDirector::Internal::Evaluation::TargetingRules.new(
        default_value: served_text, default_value_id: nil, default_variation_id: nil, rules: []
      ),
      variations: []
    )
  end

  def payload_serving(served_text)
    payload_of(integer_config_serving(served_text))
  end

  def payload_of(*config_definitions)
    ConfigDirector::Internal::Connection::ServerSdkPayload.new(
      configs: config_definitions.to_h { |definition| [definition.key, definition] }, segments: {}
    )
  end

  def client_on(connection, timeout: 5.0, hooks: ConfigDirector::ClientHooks.new)
    described_class.new(
      connection: connection, metadata: ConfigDirector::Metadata.new, timeout: timeout, logger: logger,
      hooks: hooks
    )
  end

  def seconds_taken
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  end

  it "returns from init after the timeout with one warning when the connection delivers nothing" do
    client = client_on(ScriptedConnection.new, timeout: 0.2)

    seconds = seconds_taken { client.init }

    expect(seconds).to be_between(0.2, 3)
    expect(client.ready?).to be(false)
    expect(logger.messages_at(:warn).length).to eq(1)
  end

  it "returns the in-code default value after an init that timed out" do
    client = client_on(ScriptedConnection.new, timeout: 0.05)
    client.init

    evaluation = client.evaluate("integer-config", 10)

    expect(evaluation.value).to eql(10)
    expect(evaluation.reason).to eq("client-not-ready")
  end

  it "becomes ready when the first payload arrives after init timed out" do
    connection = ScriptedConnection.new
    client = client_on(connection, timeout: 0.05)
    client.init

    connection.deliver(payload_serving("42"))

    expect(client.ready?).to be(true)
    expect(client.get_value("integer-config", 10)).to eql(42)
  end

  it "returns from init as soon as the first payload arrives from another thread" do
    connection = ScriptedConnection.new
    client = client_on(connection, timeout: 30.0)
    delivery = Thread.new do
      connection.wait_until_opened
      connection.deliver(payload_serving("42"))
    end

    seconds = seconds_taken { client.init }
    delivery.join

    expect(seconds).to be < 10
    expect(client.ready?).to be(true)
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "opens its connection once however often init is called" do
    connection = ScriptedConnection.new(payloads_delivered_when_opened: [payload_serving("42")])
    client = client_on(connection)

    client.init
    client.init

    expect(connection.open_count).to eq(1)
  end

  it "waits again, with another warning, when init is called again without values" do
    connection = ScriptedConnection.new
    client = client_on(connection, timeout: 0.05)

    client.init
    client.init

    expect(connection.open_count).to eq(1)
    expect(logger.messages_at(:warn).length).to eq(2)
  end

  it "serves a read from another thread while its connection is still opening" do
    connection = ScriptedConnection.new(opening_held: true)
    client = client_on(connection, timeout: 0.05)
    pending_init = Thread.new { client.init }
    connection.wait_until_opening

    read = Thread.new { client.evaluate("integer-config", 10) }
    read_finished = read.join(5)
    connection.release_opening
    pending_init.join

    expect(read_finished).not_to be_nil
    expect(read.value.reason).to eq("client-not-ready")
  end

  it "closes the connection that was still opening when close was called" do
    connection = ScriptedConnection.new(opening_held: true)
    client = client_on(connection, timeout: 0.05)
    pending_init = Thread.new { client.init }
    connection.wait_until_opening
    pending_close = Thread.new { client.close }

    connection.release_opening
    pending_init.join
    pending_close.join

    expect(connection.open_count).to eq(1)
    expect(connection.close_count).to eq(1)
    expect(client.closed?).to be(true)
  end

  it "does not open a connection before init" do
    connection = ScriptedConnection.new
    client_on(connection)

    expect(connection.open_count).to eq(0)
  end

  it "serves the latest payload" do
    connection = ScriptedConnection.new(payloads_delivered_when_opened: [payload_serving("1")])
    client = client_on(connection)
    client.init

    connection.deliver(payload_serving("2"))

    expect(client.get_value("integer-config", 0)).to eql(2)
  end

  it "returns a value from one payload or the other to every thread that reads while payloads arrive" do
    connection = ScriptedConnection.new(payloads_delivered_when_opened: [payload_serving("1")])
    client = client_on(connection)
    client.init
    payloads_keep_arriving = true
    evaluations_read = Queue.new
    readers = Array.new(8) do
      Thread.new do
        while payloads_keep_arriving
          evaluations_read << client.evaluate("integer-config", 0)
          Thread.pass
        end
      end
    end

    evaluations = []
    100.times do |delivery|
      connection.deliver(payload_serving(delivery.even? ? "2" : "1"))
      evaluations << evaluations_read.pop until evaluations_read.empty?
      16.times { evaluations << evaluations_read.pop }
    end
    payloads_keep_arriving = false
    readers.each(&:join)
    evaluations << evaluations_read.pop until evaluations_read.empty?

    expect(evaluations.map(&:reason).uniq).to eq(["found-match"])
    expect(evaluations.map(&:value).uniq).to contain_exactly(1, 2)
    expect(client.get_value("integer-config", 0)).to eql(1)
  end

  it "closes its connection once when closed twice" do
    connection = ScriptedConnection.new(payloads_delivered_when_opened: [payload_serving("42")])
    client = client_on(connection)
    client.init

    client.close
    client.close

    expect(connection.close_count).to eq(1)
  end

  it "does not close a connection it never opened" do
    connection = ScriptedConnection.new
    client = client_on(connection)

    client.close

    expect(connection.close_count).to eq(0)
  end

  it "stays not ready when a payload arrives after close" do
    connection = ScriptedConnection.new(payloads_delivered_when_opened: [payload_serving("1")])
    client = client_on(connection)
    client.init
    client.close

    connection.deliver(payload_serving("2"))

    expect(client.ready?).to be(false)
    expect(client.evaluate("integer-config", 0).reason).to eq("client-not-ready")
  end

  it "ends a pending init without a warning when the client is closed from another thread" do
    connection = ScriptedConnection.new
    client = client_on(connection, timeout: 30.0)
    pending_init = Thread.new { seconds_taken { client.init } }
    connection.wait_until_opened

    client.close

    expect(pending_init.value).to be < 10
    expect(client.ready?).to be(false)
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "delivers the next payload to a watch registered after init" do
    connection = ScriptedConnection.new(payloads_delivered_when_opened: [payload_serving("1")])
    client = client_on(connection)
    client.init
    values = []
    client.watch("integer-config", 0) { |value| values << value }

    connection.deliver(payload_serving("2"))

    expect(values).to eq([2])
  end

  it "names the keys a payload left out in the removed keys of configs_updated" do
    connection = ScriptedConnection.new(
      payloads_delivered_when_opened: [payload_of(integer_config_serving("1"), string_config_serving("Monday"))]
    )
    client = client_on(connection)
    client.init
    updates = []
    client.on(:configs_updated) { |update| updates << update }

    connection.deliver(payload_of(integer_config_serving("2")))

    expect(updates).to eq(
      [ConfigDirector::ConfigsUpdatedEvent.new(keys: ["integer-config"], removed_keys: ["day-of-the-week-config"])]
    )
  end

  it "delivers the in-code default value to a watch on a key the next payload left out" do
    connection = ScriptedConnection.new(
      payloads_delivered_when_opened: [payload_of(integer_config_serving("1"), string_config_serving("Monday"))]
    )
    client = client_on(connection)
    values = []
    client.watch("day-of-the-week-config", "Sunday") { |value| values << value }
    client.init

    connection.deliver(payload_of(integer_config_serving("2")))

    expect(values).to eq(%w[Monday Sunday])
  end

  it "delivers client_ready once, for the first payload only" do
    connection = ScriptedConnection.new(payloads_delivered_when_opened: [payload_serving("1")])
    ready_deliveries = []
    hooks = ConfigDirector::ClientHooks.new(client_ready: -> { ready_deliveries << :ready })
    client = client_on(connection, hooks: hooks)
    client.init

    connection.deliver(payload_serving("2"))

    expect(ready_deliveries).to eq([:ready])
  end

  it "delivers to a watch every payload that carries its key, even when the value is the same" do
    connection = ScriptedConnection.new(payloads_delivered_when_opened: [payload_serving("1")])
    client = client_on(connection)
    values = []
    client.watch("integer-config", 0) { |value| values << value }
    client.init

    connection.deliver(payload_serving("1"))

    expect(values).to eq([1, 1])
  end

  it "delivers configs_updated and the watches on the thread that delivered the payload" do
    connection = ScriptedConnection.new
    client = client_on(connection, timeout: 0.05)
    client.init
    delivering_threads = Queue.new
    client.on(:configs_updated) { |_update| delivering_threads << Thread.current }
    client.watch("integer-config", 0) { |_value| delivering_threads << Thread.current }

    delivery = Thread.new { connection.deliver(payload_serving("1")) }
    delivery.join

    expect([delivering_threads.pop, delivering_threads.pop]).to eq([delivery, delivery])
  end

  it "opens its connection once when a configs_updated handler calls init during init" do
    connection = ScriptedConnection.new(payloads_delivered_when_opened: [payload_serving("42")])
    client = client_on(connection)
    client.on(:configs_updated) { |_update| client.init }

    client.init

    expect(connection.open_count).to eq(1)
    expect(logger.messages_at(:error)).to be_empty
  end
end
