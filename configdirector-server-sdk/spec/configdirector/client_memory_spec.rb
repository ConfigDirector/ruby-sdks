# frozen_string_literal: true

require "logger"
require_relative "../support/client_of_the_scripted_sdk_server"

RSpec.describe "The memory and the threads a client holds" do
  include_context "with a client of the scripted SDK server"

  let(:logger) { Logger.new(File::NULL, level: :warn) }
  let(:most_objects_gained) { 5_000 }
  let(:payload_of_20_configs) do
    full_payload_text(
      configs: Array.new(20) do |number|
        wire_config(
          "config-#{number}", "outside-beta",
          rules: [wire_rule_serving("inside-beta", conditions: [wire_segment_condition("beta")])]
        )
      end,
      segments: { "beta" => wire_segment_of_contexts_with_trait("/plan", "pro") }
    )
  end

  def objects_alive_after_a_collection
    3.times { GC.start }

    GC.stat(:heap_live_slots)
  end

  def read_for_as_many_contexts(count, client)
    count.times do |number|
      context = ConfigDirector::Context.new(id: "user-#{number}", traits: { plan: "pro", seats: number })
      client.get_value("config-#{number % 20}", "in-code", context)
    end
  end

  def thread_opening_every_stream_with(payload_text)
    sdk_server.url
    Thread.new do
      loop do
        stream_request = sdk_server.request_to(ScriptedSdkServer::STREAM_PATH, within: nil)
        stream_request.open_event_stream
        stream_request.send_event(payload_text)
      end
    end
  end

  def create_initialize_and_close_as_many_clients(count)
    count.times do
      client = ConfigDirector.create_client(
        "server-sdk-key", connection: ConfigDirector::ConnectionOptions.new(url: sdk_server.url), logger: logger
      )
      client.init
      client.get_value("config-1", "in-code")
      client.close
    end
    wait_until_no_sdk_thread_is_alive
  end

  it "holds as many objects after 100,000 reads as after 1,000, with a telemetry queue of 100 events" do
    client, = streaming_client_initialized_with(
      payload_of_20_configs, telemetry: ConfigDirector::TelemetryOptions.new(event_queue_limit: 100)
    )

    read_for_as_many_contexts(1_000, client)
    objects_after_1_000_reads = objects_alive_after_a_collection
    read_for_as_many_contexts(99_000, client)
    objects_after_100_000_reads = objects_alive_after_a_collection

    expect(objects_after_100_000_reads - objects_after_1_000_reads).to be < most_objects_gained
  end

  it "holds as many objects after 1,000 full payloads as after 10" do
    client, stream_request = streaming_client_initialized_with(payload_of_20_configs)
    updates = updates_received_by(client)
    take_in_as_many_payloads = lambda do |count|
      count.times do
        stream_request.send_event(payload_of_20_configs)
        updates.pop(timeout: 5)
      end
    end

    take_in_as_many_payloads.call(10)
    objects_after_10_payloads = objects_alive_after_a_collection
    take_in_as_many_payloads.call(990)
    objects_after_1_000_payloads = objects_alive_after_a_collection

    expect(objects_after_1_000_payloads - objects_after_10_payloads).to be < most_objects_gained
  end

  it "holds as many objects after 20,000 watches and handlers were added and removed as after 100" do
    client, = streaming_client_initialized_with(payload_of_20_configs)
    add_and_remove_as_many = lambda do |count|
      count.times do
        client.watch("config-1", "in-code") { |_value| nil }.close
        client.watch("config-2", "in-code") { |_value| nil }
        client.unwatch("config-2")
        client.on(:configs_updated) { |_update| nil }.close
        client.on(:config_evaluated) { |_event| nil }
        client.off(:config_evaluated)
      end
    end

    add_and_remove_as_many.call(100)
    objects_after_100_additions = objects_alive_after_a_collection
    add_and_remove_as_many.call(19_900)
    objects_after_20_000_additions = objects_alive_after_a_collection

    expect(objects_after_20_000_additions - objects_after_100_additions).to be < most_objects_gained
  end

  it "leaves as many threads and objects after 60 clients were created, initialized and closed as after 10" do
    thread_opening_every_stream = thread_opening_every_stream_with(payload_of_20_configs)

    create_initialize_and_close_as_many_clients(10)
    threads_after_10_clients = Thread.list.length
    objects_after_10_clients = objects_alive_after_a_collection
    create_initialize_and_close_as_many_clients(50)

    expect(Thread.list.length).to eq(threads_after_10_clients)
    expect(objects_alive_after_a_collection - objects_after_10_clients).to be < most_objects_gained
  ensure
    thread_opening_every_stream&.kill
  end
end
