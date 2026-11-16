# frozen_string_literal: true

require_relative "../support/client_of_the_scripted_sdk_server"

RSpec.describe "A client given malformed or oversized input" do
  include_context "with a client of the scripted SDK server"

  let(:payload_serving_monday) { full_payload_text(configs: [wire_config("day-of-the-week", "Monday")]) }
  let(:payload_serving_tuesday) { full_payload_text(configs: [wire_config("day-of-the-week", "Tuesday")]) }
  let(:number_of_16_385_digits) { "7" * 16_385 }

  def day_served_after_the_next_update(client, updates)
    updates.pop(timeout: 5)

    client.get_value("day-of-the-week", "Sunday")
  end

  def evaluation_of_a_config_serving(served_text, type, in_code_default_value)
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [wire_config("hostile", served_text, type: type)])
    )

    client.evaluate("hostile", in_code_default_value)
  end

  def day_served_by_a_rule_on_the_trait(trait_pointer, context)
    rule_on_the_trait = wire_rule_serving("Tuesday", conditions: [wire_trait_condition(trait_pointer, "pro")])
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [wire_config("day-of-the-week", "Monday", rules: [rule_on_the_trait])])
    )

    client.get_value("day-of-the-week", "Sunday", context)
  end

  it "serves the next payload on its streaming thread after a payload that holds a number of 16,385 digits" do
    client, stream_request = streaming_client_initialized_with(payload_serving_monday)
    updates = updates_received_by(client)

    stream_request.send_event("{\"configs\":{},\"timestamp\":#{number_of_16_385_digits}}")
    stream_request.send_event(payload_serving_tuesday)

    expect(day_served_after_the_next_update(client, updates)).to eq("Tuesday")
    expect(updates).to be_empty
    expect(logger.messages_at(:error)).to eq(
      [
        "[StreamingTransport] Error parsing and dispatching config data update: " \
        'JSON::ParserError: "it holds a number of more than 16,384 digits"'
      ]
    )
  end

  it "serves the next payload of a stream that replaces one with a line of more than 1 MiB" do
    client, stream_request = streaming_client_initialized_with(payload_serving_monday)
    updates = updates_received_by(client)

    stream_request.send_stream_text("data: #{"x" * 1_048_577}")
    stream_of_the_next_attempt = sdk_server.next_stream_request(within: 10)
    stream_of_the_next_attempt.open_event_stream
    stream_of_the_next_attempt.send_event(payload_serving_tuesday)

    expect(day_served_after_the_next_update(client, updates)).to eq("Tuesday")
    expect(sdk_threads_alive.map(&:name)).to include("configdirector-streaming")
  end

  it "returns from init with one error when the first poll is answered with a number of 16,385 digits" do
    client = client_connecting_to(sdk_server.url, mode: "polling")

    initialize_with_a_first_poll_answered(
      client, status: 200, body: "{\"configs\":{},\"timestamp\":#{number_of_16_385_digits}}"
    )

    expect(client.ready?).to be(false)
    expect(logger.messages_at(:error)).to eq(
      [
        "[PollingTransport] Error during polling: Failed to parse the response from the server: " \
        "it holds a number of more than 16,384 digits"
      ]
    )
    expect(sdk_threads_alive.map(&:name)).to include("configdirector-polling")
  end

  it "returns the in-code default value of a JSON config whose value holds a number of 16,385 digits" do
    evaluation = evaluation_of_a_config_serving("[#{number_of_16_385_digits}]", "json", [])

    expect([evaluation.value, evaluation.reason]).to eq([[], "invalid-json"])
  end

  it "returns the in-code default value of an integer config whose value has 100,000 digits" do
    evaluation = evaluation_of_a_config_serving("7" * 100_000, "integer", 5)

    expect([evaluation.value, evaluation.reason]).to eq([5, "invalid-number"])
  end

  it "returns the in-code default value of a float config whose value has 100,000 digits" do
    evaluation = evaluation_of_a_config_serving("7" * 100_000, "float", 0.5)

    expect([evaluation.value, evaluation.reason]).to eq([0.5, "invalid-number"])
  end

  it "returns the in-code default value of a boolean config whose value has 100,000 characters" do
    evaluation = evaluation_of_a_config_serving("true" * 25_000, "boolean", false)

    expect([evaluation.value, evaluation.reason]).to eq([false, "invalid-boolean"])
  end

  it "serves the default targeting rule value when a rule looks up a trait 100,000 levels deep" do
    context = ConfigDirector::Context.new(id: "user-123", traits: { "plan" => "pro" })

    expect(day_served_by_a_rule_on_the_trait("/plan" * 100_000, context)).to eq("Monday")
  end

  it "serves the default targeting rule value when a rule looks up an array element of 100,000 digits" do
    context = ConfigDirector::Context.new(id: "user-123", traits: { "plans" => %w[pro team] })

    expect(day_served_by_a_rule_on_the_trait("/plans/#{"9" * 100_000}", context)).to eq("Monday")
  end

  it "serves the default targeting rule value when the trait a rule looks up is a list" do
    context = ConfigDirector::Context.new(id: "user-123", traits: { "plan" => ["pro", Float::NAN, 10**400, nil] })

    expect(day_served_by_a_rule_on_the_trait("/plan", context)).to eq("Monday")
    expect(logger.messages_at(:error)).to be_empty
  end

  it "serves the default targeting rule value when the trait a rule looks up is an object of the application" do
    context = ConfigDirector::Context.new(id: "user-123", traits: { "plan" => Object.new })

    expect(day_served_by_a_rule_on_the_trait("/plan", context)).to eq("Monday")
    expect(logger.messages_at(:error)).to be_empty
  end

  it "serves a rollout share whose percentage is a whole number too large for a Float" do
    rollout = wire_rollout_to_everyone("Tuesday")
    rollout.fetch("percentages").first["percentage"] = 10**400
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [wire_config("day-of-the-week", "Monday", rules: [rollout])])
    )

    expect(client.get_value("day-of-the-week", "Sunday", ConfigDirector::Context.new(id: "user-123"))).to eq("Tuesday")
    expect(logger.messages_at(:error)).to be_empty
  end
end
