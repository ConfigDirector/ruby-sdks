# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Telemetry::ReportedEvaluation do
  def config_read_with(in_code_default_value)
    ConfigDirector::Internal::Client::ConfigRead.new(
      config_key: "banner", context: nil,
      in_code_default_value: ConfigDirector::Internal::Value::InCodeDefaultValue.from(in_code_default_value)
    )
  end

  def config_state_serving(text, type:, value_id:)
    ConfigDirector::ConfigState.new(id: "id-of-banner", key: "banner", type: type, value: text, value_id: value_id)
  end

  it "keeps nothing of a JSON value that ConfigDirector sent with a value ID" do
    config_state = config_state_serving('{"greeting":"hello"}', type: "json", value_id: "value-id-of-banner")
    evaluated_read = config_read_with({}).evaluated_to(
      ConfigDirector::Internal::Value::TypedValue.new(value: { "greeting" => "hello" }), config_state, "found-match"
    )

    expect(described_class.of(evaluated_read).value_kept_for_the_report).to be_nil
  end

  it "keeps a JSON value that was sent without a value ID" do
    config_state = config_state_serving('{"greeting":"hello"}', type: "json", value_id: nil)
    evaluated_read = config_read_with({}).evaluated_to(
      ConfigDirector::Internal::Value::TypedValue.new(value: { "greeting" => "hello" }), config_state, "found-match"
    )

    expect(described_class.of(evaluated_read).value_kept_for_the_report).to eq("greeting" => "hello")
  end

  it "keeps a text value that ConfigDirector sent with a value ID" do
    config_state = config_state_serving("hello", type: "string", value_id: "value-id-of-banner")
    evaluated_read = config_read_with("none").evaluated_to(
      ConfigDirector::Internal::Value::TypedValue.new(value: "hello"), config_state, "found-match"
    )

    expect(described_class.of(evaluated_read).value_kept_for_the_report).to eq("hello")
  end
end
