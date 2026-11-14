# frozen_string_literal: true

require_relative "../support/recording_logger"

RSpec.describe "Getting all configs" do
  let(:client) { ConfigDirector.create_client("server-sdk-key", logger: RecordingLogger.new) }

  it "returns no configs before init" do
    expect(client.get_all_configs).to eq({})
  end

  it "returns a state for every config, keyed by config key" do
    client.init

    expect(client.get_all_configs.keys).to contain_exactly(
      "temporary-feature-flag", "permanent-kill-switch", "integer-config", "day-of-the-week-config",
      "json-value-config", "json-list-config", "float-config", "config-without-a-value", "malformed-json-config"
    )
  end

  it "returns the state of a config: its ID, key, type, served text and value ID" do
    client.init

    expect(client.get_all_configs.fetch("integer-config")).to eq(
      ConfigDirector::ConfigState.new(
        id: "9a3e5b71-6c2d-4f08-8b1a-4d7c2e9f5a03", key: "integer-config", type: "integer", value: "42",
        value_id: "value-integer-42"
      )
    )
  end

  it "returns the variation, targeting rule and share of a percentage rollout" do
    client.init

    state = client.get_all_configs(context: ConfigDirector::Context.new(id: "user-123")).fetch("temporary-feature-flag")

    expect(state.value).to eq("true")
    expect(state.value_id).to eq("value-flag-on")
    expect(state.variation).to eq(ConfigDirector::Variation.new(id: "variation-flag-on", name: "On"))
    expect(state.rule_id).to eq("rule-flag-rollout")
    expect(state.share_id).to eq("share-flag-on")
  end

  it "returns the default targeting rule value of a percentage rollout when no context is given" do
    client.init

    state = client.get_all_configs.fetch("temporary-feature-flag")

    expect(state.value).to eq("false")
    expect(state.variation).to eq(ConfigDirector::Variation.new(id: "variation-flag-off", name: "Off"))
    expect(state.rule_id).to be_nil
    expect(state.share_id).to be_nil
  end

  it "evaluates the targeting rules for the context" do
    client.init
    pro_context = ConfigDirector::Context.new(traits: { "plan" => "pro" })

    expect(client.get_all_configs(context: pro_context).fetch("day-of-the-week-config").value).to eq("Tuesday")
  end

  it "returns only the listed config keys" do
    client.init

    states = client.get_all_configs(config_keys: %w[integer-config float-config no-such-config])

    expect(states.keys).to contain_exactly("integer-config", "float-config")
  end

  it "returns no configs for an empty list of config keys" do
    client.init

    expect(client.get_all_configs(config_keys: [])).to eq({})
  end

  it "raises for config keys given as one String" do
    client.init

    expect { client.get_all_configs(config_keys: "integer-config") }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises for config keys that are not a list" do
    client.init

    expect { client.get_all_configs(config_keys: 5) }.to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "returns states that cannot be changed" do
    client.init

    expect(client.get_all_configs.fetch("integer-config")).to be_frozen
  end

  it "raises for a context that is a Hash" do
    client.init

    expect { client.get_all_configs(context: { id: "user-123" }) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end
end
