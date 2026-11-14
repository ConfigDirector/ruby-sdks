# frozen_string_literal: true

require_relative "../support/recording_logger"

RSpec.describe "Reading a config" do
  let(:client) { ConfigDirector.create_client("server-sdk-key", logger: RecordingLogger.new) }
  let(:identified_context) { ConfigDirector::Context.new(id: "user-123") }

  before { client.init }

  it "returns the value a boolean config serves" do
    evaluation = client.evaluate("permanent-kill-switch", false)

    expect(evaluation.value).to be(true)
    expect(evaluation.reason).to eq("found-match")
  end

  it "returns the value a string config serves" do
    evaluation = client.evaluate("day-of-the-week-config", "Sunday")

    expect(evaluation.value).to eq("Monday")
    expect(evaluation.reason).to eq("found-match")
  end

  it "returns the value an integer config serves" do
    evaluation = client.evaluate("integer-config", 10)

    expect(evaluation.value).to eql(42)
    expect(evaluation.reason).to eq("found-match")
  end

  it "returns the value a float config serves" do
    evaluation = client.evaluate("float-config", 1.5)

    expect(evaluation.value).to eql(26.0)
    expect(evaluation.reason).to eq("found-match")
  end

  it "returns a JSON object as a Hash with String keys" do
    evaluation = client.evaluate("json-value-config", {})

    expect(evaluation.value).to eq({ "greeting" => "hello", "sizes" => [1, 2] })
    expect(evaluation.reason).to eq("found-match")
  end

  it "returns a JSON array as an Array" do
    evaluation = client.evaluate("json-list-config", [])

    expect(evaluation.value).to eq(%w[small large])
    expect(evaluation.reason).to eq("found-match")
  end

  it "returns the text of a JSON config for a String in-code default value" do
    evaluation = client.evaluate("json-list-config", "none")

    expect(evaluation.value).to eq('["small","large"]')
    expect(evaluation.reason).to eq("found-match")
  end

  it "returns an Integer for a whole number written with a decimal point" do
    evaluation = client.evaluate("float-config", 10)

    expect(evaluation.value).to eql(26)
    expect(evaluation.reason).to eq("found-match")
  end

  it "returns a Float for an integer config read with a Float in-code default value" do
    evaluation = client.evaluate("integer-config", 1.5)

    expect(evaluation.value).to eql(42.0)
    expect(evaluation.reason).to eq("found-match")
  end

  it "returns the value of the targeting rule that matches the context's traits" do
    pro_context = ConfigDirector::Context.new(id: "user-123", traits: { "plan" => "pro" })

    expect(client.get_value("day-of-the-week-config", "Sunday", pro_context)).to eq("Tuesday")
  end

  it "returns the value of the targeting rule that matches the application's metadata" do
    beta_client = ConfigDirector.create_client(
      "server-sdk-key", metadata: ConfigDirector::Metadata.new(app_name: "beta-app"), logger: RecordingLogger.new
    )
    beta_client.init

    expect(beta_client.get_value("integer-config", 10)).to eql(7)
  end

  it "returns the value of a percentage rollout to a context with an id" do
    evaluation = client.evaluate("temporary-feature-flag", false, identified_context)

    expect(evaluation.value).to be(true)
    expect(evaluation.reason).to eq("found-match")
  end

  it "returns the default targeting rule value when a percentage rollout is skipped for a context without an id" do
    evaluation = client.evaluate("temporary-feature-flag", true, ConfigDirector::Context.new(name: "Ada"))

    expect(evaluation.value).to be(false)
    expect(evaluation.default_value?).to be(false)
    expect(evaluation.reason).to eq("rollout-skipped-no-identifier")
  end

  it "returns the in-code default value when no config has the key" do
    evaluation = client.evaluate("no-such-config", "in-code")

    expect(evaluation.value).to eq("in-code")
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("config-state-missing")
  end

  it "returns the in-code default value for a blank config key" do
    evaluation = client.evaluate(" ", 5)

    expect(evaluation.value).to eql(5)
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("config-state-missing")
  end

  it "returns the in-code default value for a config key that is not a String" do
    evaluation = client.evaluate(:"integer-config", 5)

    expect(evaluation.value).to eql(5)
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("config-state-missing")
  end

  it "returns the in-code default value when a String is read from an integer config" do
    evaluation = client.evaluate("integer-config", "in-code")

    expect(evaluation.value).to eq("in-code")
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("type-mismatch")
  end

  it "returns the in-code default value when the config has no value" do
    evaluation = client.evaluate("config-without-a-value", "in-code")

    expect(evaluation.value).to eq("in-code")
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("value-missing")
  end

  it "returns the in-code default value when an Integer is read from text that is not a number" do
    evaluation = client.evaluate("day-of-the-week-config", 5)

    expect(evaluation.value).to eql(5)
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("invalid-number")
  end

  it "returns the in-code default value when a Float is read from text that is not a number" do
    evaluation = client.evaluate("day-of-the-week-config", 2.5)

    expect(evaluation.value).to eql(2.5)
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("invalid-number")
  end

  it "returns the in-code default value when a Hash is read from malformed JSON" do
    evaluation = client.evaluate("malformed-json-config", { "greeting" => "in-code" })

    expect(evaluation.value).to eq({ "greeting" => "in-code" })
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("invalid-json")
  end

  it "returns the in-code default value when a Hash is read from a JSON array" do
    evaluation = client.evaluate("json-list-config", { "greeting" => "in-code" })

    expect(evaluation.value).to eq({ "greeting" => "in-code" })
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("invalid-json")
  end

  it "returns the in-code default value when an Array is read from a JSON object" do
    evaluation = client.evaluate("json-value-config", ["in-code"])

    expect(evaluation.value).to eq(["in-code"])
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("invalid-json")
  end

  it "returns the in-code default value when a boolean is read from a value that is neither true nor false" do
    evaluation = client.evaluate("integer-config", true)

    expect(evaluation.value).to be(true)
    expect(evaluation.default_value?).to be(true)
    expect(evaluation.reason).to eq("invalid-boolean")
  end

  it "returns the value of an evaluation from get_value" do
    expect(client.get_value("integer-config", 10)).to eql(42)
  end

  it "returns the in-code default value from get_value when no config has the key" do
    expect(client.get_value("no-such-config", 10)).to eql(10)
  end

  it "reports the key, value ID, variation and context of a served value" do
    evaluation = client.evaluate("temporary-feature-flag", false, identified_context)

    expect(evaluation.key).to eq("temporary-feature-flag")
    expect(evaluation.value_id).to eq("value-flag-on")
    expect(evaluation.variation).to eq(ConfigDirector::Variation.new(id: "variation-flag-on", name: "On"))
    expect(evaluation.default_value?).to be(false)
    expect(evaluation.context).to be(identified_context)
  end

  it "reports no variation for a config without variations" do
    evaluation = client.evaluate("integer-config", 10)

    expect(evaluation.value_id).to eq("value-integer-42")
    expect(evaluation.variation).to be_nil
    expect(evaluation.context).to be_nil
  end

  it "reports no value ID and no variation when the in-code default value is returned" do
    evaluation = client.evaluate("temporary-feature-flag", "in-code", identified_context)

    expect(evaluation.reason).to eq("type-mismatch")
    expect(evaluation.key).to eq("temporary-feature-flag")
    expect(evaluation.value_id).to be_nil
    expect(evaluation.variation).to be_nil
    expect(evaluation.context).to be(identified_context)
  end

  it "returns the in-code default value for a config key that is not valid text" do
    evaluation = client.evaluate("caf\xE9".b, "d\u00E9j\u00E0 vu")

    expect(evaluation.value).to eq("d\u00E9j\u00E0 vu")
    expect(evaluation.reason).to eq("config-state-missing")
  end

  it "builds no debug line for a logger that does not log at debug level" do
    logger_at_warn_level = Class.new(RecordingLogger) do
      def debug?
        false
      end
    end.new
    quiet_client = ConfigDirector.create_client("server-sdk-key", logger: logger_at_warn_level)
    quiet_client.init

    quiet_client.get_value("integer-config", 10)

    expect(logger_at_warn_level.messages_at(:debug)).to be_empty
  end

  it "returns an evaluation equal to one built with the same values" do
    expect(client.evaluate("integer-config", 10)).to eq(
      ConfigDirector::ConfigEvaluation.new(
        key: "integer-config", value: 42, default_value: false, reason: "found-match", value_id: "value-integer-42"
      )
    )
  end

  it "returns an evaluation that cannot be changed" do
    expect(client.evaluate("integer-config", 10)).to be_frozen
  end

  it "raises for a nil in-code default value" do
    expect { client.get_value("integer-config", nil) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises for a Symbol in-code default value" do
    expect { client.evaluate("day-of-the-week-config", :sunday) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises for an in-code default value of an unsupported class" do
    expect { client.evaluate("float-config", Rational(1, 2)) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises for a context that is a Hash" do
    expect { client.get_value("integer-config", 10, { id: "user-123" }) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end
end
