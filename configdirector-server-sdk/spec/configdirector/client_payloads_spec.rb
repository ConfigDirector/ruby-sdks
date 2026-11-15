# frozen_string_literal: true

require_relative "../support/client_of_the_scripted_sdk_server"

RSpec.describe "The server SDK payloads a client receives" do
  include_context "with a client of the scripted SDK server"

  let(:checkout_for_the_beta_segment) do
    wire_config(
      "checkout", "old-checkout",
      rules: [wire_rule_serving("new-checkout", conditions: [wire_segment_condition("beta")])]
    )
  end
  let(:banner) { wire_config("banner", "hidden") }
  let(:limits) { wire_config("limits", "10", type: "integer") }
  let(:beta_segment_of_the_pro_plan) { { "beta" => wire_segment_of_contexts_with_trait("/plan", "pro") } }
  let(:beta_segment_of_the_team_plan) { { "beta" => wire_segment_of_contexts_with_trait("/plan", "team") } }
  let(:context_on_the_pro_plan) { ConfigDirector::Context.new(id: "user-123", traits: { "plan" => "pro" }) }
  let(:context_on_the_team_plan) { ConfigDirector::Context.new(id: "user-456", traits: { "plan" => "team" }) }

  let(:payload_for_the_pro_plan) do
    full_payload_text(
      configs: [
        wire_config("checkout", "outside-pro",
                    rules: [wire_rule_serving("inside-pro", conditions: [wire_segment_condition("beta")])]),
        wire_config("banner", "banner-of-pro")
      ],
      segments: beta_segment_of_the_pro_plan
    )
  end
  let(:payload_for_the_team_plan) do
    full_payload_text(
      configs: [
        wire_config("checkout", "outside-team",
                    rules: [wire_rule_serving("inside-team", conditions: [wire_segment_condition("beta")])]),
        wire_config("banner", "banner-of-team")
      ],
      segments: beta_segment_of_the_team_plan
    )
  end

  def checkout_serving_new_checkout_when(*conditions)
    wire_config("checkout", "old-checkout", rules: [wire_rule_serving("new-checkout", conditions: conditions)])
  end

  def skipped_config_warning(config_key)
    "[ConfigDirectorClient] Skipping the config '#{config_key}', its definition could not be read: "
  end

  it "names a config a delta adds in configs_updated, serves it and calls a watch on it" do
    client, stream_request = streaming_client_initialized_with(full_payload_text(configs: [limits]))
    updates = updates_received_by(client)
    values_of_the_watch = Queue.new
    client.watch("banner", "in-code") { |value| values_of_the_watch << value }

    stream_request.send_event(delta_payload_text(configs: [wire_config("banner", "shown")]))

    expect(updates.pop(timeout: 5)).to eq(ConfigDirector::ConfigsUpdatedEvent.new(keys: ["banner"], removed_keys: []))
    expect(values_of_the_watch.pop(timeout: 5)).to eq("shown")
    expect(client.get_value("banner", "in-code")).to eq("shown")
    expect(client.get_value("limits", 0)).to eql(10)
  end

  it "names a config a full payload no longer carries in removed_keys and stops serving it" do
    client, stream_request = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_for_the_beta_segment, banner, limits])
    )
    updates = updates_received_by(client)
    values_of_the_watch = Queue.new
    client.watch("limits", 0) { |value| values_of_the_watch << value }

    stream_request.send_event(full_payload_text(configs: [banner, checkout_for_the_beta_segment]))

    expect(updates.pop(timeout: 5)).to eq(
      ConfigDirector::ConfigsUpdatedEvent.new(keys: %w[banner checkout], removed_keys: ["limits"])
    )
    expect(values_of_the_watch.pop(timeout: 5)).to eql(0)
    expect(client.evaluate("limits", 0).reason).to eq("config-state-missing")
    expect(client.get_all_configs.keys).to eq(%w[banner checkout])
  end

  it "names the configs that use a segment when a delta carries only that segment, and evaluates them with it" do
    client, stream_request = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_for_the_beta_segment, banner], segments: beta_segment_of_the_pro_plan)
    )
    served_before_the_delta = client.get_value("checkout", "in-code", context_on_the_team_plan)
    updates = updates_received_by(client)
    values_of_the_watch = Queue.new
    client.watch("checkout", "in-code", context_on_the_team_plan) { |value| values_of_the_watch << value }

    stream_request.send_event(delta_payload_text(segments: beta_segment_of_the_team_plan))

    expect(updates.pop(timeout: 5)).to eq(
      ConfigDirector::ConfigsUpdatedEvent.new(keys: ["checkout"], removed_keys: [])
    )
    expect(values_of_the_watch.pop(timeout: 5)).to eq("new-checkout")
    expect(served_before_the_delta).to eq("old-checkout")
    expect(client.get_value("checkout", "in-code", context_on_the_team_plan)).to eq("new-checkout")
    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("old-checkout")
  end

  it "names the configs of a delta before the configs that use a segment the delta carries" do
    client, stream_request = streaming_client_initialized_with(
      full_payload_text(
        configs: [checkout_for_the_beta_segment, banner, limits], segments: beta_segment_of_the_pro_plan
      )
    )
    updates = updates_received_by(client)

    stream_request.send_event(
      delta_payload_text(configs: [wire_config("limits", "20", type: "integer")],
                         segments: beta_segment_of_the_team_plan)
    )

    expect(updates.pop(timeout: 5)).to eq(
      ConfigDirector::ConfigsUpdatedEvent.new(keys: %w[limits checkout], removed_keys: [])
    )
  end

  it "names a config once when a delta carries it and a segment it uses" do
    client, stream_request = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_for_the_beta_segment], segments: beta_segment_of_the_pro_plan)
    )
    updates = updates_received_by(client)

    stream_request.send_event(
      delta_payload_text(configs: [checkout_for_the_beta_segment], segments: beta_segment_of_the_team_plan)
    )

    expect(updates.pop(timeout: 5)).to eq(
      ConfigDirector::ConfigsUpdatedEvent.new(keys: ["checkout"], removed_keys: [])
    )
  end

  it "does not name a config that uses another segment than the one a delta carries" do
    client, stream_request = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_for_the_beta_segment], segments: beta_segment_of_the_pro_plan)
    )
    updates = updates_received_by(client)

    stream_request.send_event(
      delta_payload_text(segments: { "staff" => wire_segment_of_contexts_with_trait("/plan", "team") })
    )

    expect(updates.pop(timeout: 5)).to eq(ConfigDirector::ConfigsUpdatedEvent.new(keys: [], removed_keys: []))
  end

  it "does not name a config whose only use of a carried segment is in a rule of a type it does not know" do
    scheduled_rule = wire_rule_serving("scheduled-checkout", conditions: [wire_segment_condition("beta")])
                     .merge("type" => "scheduled")
    client, stream_request = streaming_client_initialized_with(
      full_payload_text(
        configs: [wire_config("checkout", "old-checkout", rules: [scheduled_rule])],
        segments: beta_segment_of_the_pro_plan
      )
    )
    updates = updates_received_by(client)

    stream_request.send_event(delta_payload_text(segments: beta_segment_of_the_team_plan))

    expect(updates.pop(timeout: 5)).to eq(ConfigDirector::ConfigsUpdatedEvent.new(keys: [], removed_keys: []))
  end

  it "keeps the segments it holds when a delta carries none" do
    client, stream_request = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_for_the_beta_segment], segments: beta_segment_of_the_pro_plan)
    )
    updates = updates_received_by(client)

    stream_request.send_event(delta_payload_text(configs: [banner]))
    updates.pop(timeout: 5)

    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("new-checkout")
  end

  it "drops the segments a full payload no longer carries" do
    client, stream_request = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_for_the_beta_segment], segments: beta_segment_of_the_pro_plan)
    )
    updates = updates_received_by(client)

    stream_request.send_event(full_payload_text(configs: [checkout_for_the_beta_segment]))
    updates.pop(timeout: 5)

    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("old-checkout")
  end

  it "reads a payload of a kind it does not know as a full payload" do
    client, stream_request = streaming_client_initialized_with(full_payload_text(configs: [banner, limits]))
    updates = updates_received_by(client)

    stream_request.send_event(JSON.generate(wire_payload("snapshot", [banner], {})))

    expect(updates.pop(timeout: 5)).to eq(
      ConfigDirector::ConfigsUpdatedEvent.new(keys: ["banner"], removed_keys: ["limits"])
    )
  end

  it "serves a payload whatever its payloadVersion" do
    client, = streaming_client_initialized_with(
      JSON.generate(wire_payload("full", [banner], {}).merge("payloadVersion" => 2))
    )

    expect(client.get_value("banner", "in-code")).to eq("hidden")
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "ignores a top-level field it does not know" do
    client, = streaming_client_initialized_with(
      JSON.generate(wire_payload("full", [banner], {}).merge("experiments" => { "checkout-test" => { "arms" => 2 } }))
    )

    expect(client.get_value("banner", "in-code")).to eq("hidden")
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "ignores a field of a condition it does not know" do
    condition = wire_trait_condition("/plan", "pro").merge("caseSensitive" => false)
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_serving_new_checkout_when(condition)])
    )

    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("new-checkout")
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "ignores a field of a config, a rule and a segment it does not know" do
    rule = wire_rule_serving("new-checkout", conditions: [wire_segment_condition("beta")]).merge("schedule" => {})
    checkout = wire_config("checkout", "old-checkout", rules: [rule]).merge("description" => "The new checkout")
    segment = wire_segment_of_contexts_with_trait("/plan", "pro").merge("name" => "Beta testers")
    client, = streaming_client_initialized_with(full_payload_text(configs: [checkout], segments: { "beta" => segment }))

    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("new-checkout")
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "never serves from a rule of a type it does not know, and serves the config's other rules" do
    scheduled_rule = wire_rule_serving("scheduled-checkout", conditions: []).merge("type" => "scheduled")
    rule_for_the_pro_plan = wire_rule_serving("new-checkout", conditions: [wire_trait_condition("/plan", "pro")])
                            .merge("order" => 1)
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [wire_config("checkout", "old-checkout", rules: [scheduled_rule,
                                                                                  rule_for_the_pro_plan])])
    )

    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("new-checkout")
    expect(client.get_value("checkout", "in-code", context_on_the_team_plan)).to eq("old-checkout")
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "serves the rule with the lowest order first, wherever the payload lists it" do
    rule_listed_first = wire_rule_serving("listed-first", conditions: []).merge("order" => 1)
    rule_ordered_first = wire_rule_serving("ordered-first", conditions: []).merge("order" => 0)
    client, = streaming_client_initialized_with(
      full_payload_text(
        configs: [wire_config("checkout", "old-checkout", rules: [rule_listed_first, rule_ordered_first])]
      )
    )

    expect(client.get_value("checkout", "in-code")).to eq("ordered-first")
  end

  it "reports the value ID and the variation of the targeting rule that served the value" do
    rule = wire_rule_serving("new-checkout", conditions: []).merge("variationId" => "variation-new")
    checkout = wire_config(
      "checkout", "old-checkout",
      rules: [rule], variations: [{ "id" => "variation-new", "name" => "New checkout", "value" => "new-checkout" }]
    )
    client, = streaming_client_initialized_with(full_payload_text(configs: [checkout]))

    evaluation = client.evaluate("checkout", "in-code")

    expect(evaluation.value_id).to eq("value-id-of-new-checkout")
    expect(evaluation.variation).to eq(ConfigDirector::Variation.new(id: "variation-new", name: "New checkout"))
  end

  it "reads a condition without a kind as an attribute condition" do
    client, = streaming_client_initialized_with(
      full_payload_text(
        configs: [checkout_serving_new_checkout_when(wire_trait_condition("/plan", "pro").except("kind"))]
      )
    )

    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("new-checkout")
    expect(client.get_value("checkout", "in-code", context_on_the_team_plan)).to eq("old-checkout")
  end

  it "reads a target value that is a number as its text" do
    condition = wire_trait_condition("/seats", "unused").merge("targetValues" => [26])
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_serving_new_checkout_when(condition)])
    )

    expect(client.get_value("checkout", "in-code", ConfigDirector::Context.new(traits: { "seats" => "26" })))
      .to eq("new-checkout")
  end

  it "reads a target value that is a boolean as its text" do
    condition = wire_trait_condition("/trial", "unused").merge("targetValues" => [true])
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_serving_new_checkout_when(condition)])
    )

    expect(client.get_value("checkout", "in-code", ConfigDirector::Context.new(traits: { "trial" => "true" })))
      .to eq("new-checkout")
  end

  it "skips a config without a target with one warning and serves the other configs" do
    client, = streaming_client_initialized_with(full_payload_text(configs: [banner.except("target"), limits]))

    evaluation = client.evaluate("banner", "in-code")

    expect(evaluation.value).to eq("in-code")
    expect(evaluation.reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(client.get_all_configs.keys).to eq(["limits"])
    expect(logger.messages_at(:warn)).to eq(
      ["[ConfigDirectorClient] Skipping the config 'banner', its definition could not be read: " \
       "the config has no target"]
    )
  end

  it "names only the configs it could read in the keys of configs_updated" do
    client = client_connecting_to(sdk_server.url)
    updates = updates_received_by(client)

    initialize_over_a_stream_carrying(full_payload_text(configs: [banner.except("target"), limits]), client)

    expect(updates.pop(timeout: 5)).to eq(ConfigDirector::ConfigsUpdatedEvent.new(keys: ["limits"], removed_keys: []))
  end

  it "names a config it held in removed_keys when a full payload carries it without a target" do
    client, stream_request = streaming_client_initialized_with(full_payload_text(configs: [banner, limits]))
    updates = updates_received_by(client)
    values_of_the_watch = Queue.new
    client.watch("banner", "in-code") { |value| values_of_the_watch << value }

    stream_request.send_event(full_payload_text(configs: [banner.except("target"), limits]))

    expect(updates.pop(timeout: 5)).to eq(
      ConfigDirector::ConfigsUpdatedEvent.new(keys: ["limits"], removed_keys: ["banner"])
    )
    expect(values_of_the_watch.pop(timeout: 5)).to eq("in-code")
    expect(client.evaluate("banner", "in-code").reason).to eq("config-state-missing")
  end

  it "names a config it held in removed_keys when a delta carries it without a target" do
    client, stream_request = streaming_client_initialized_with(full_payload_text(configs: [banner, limits]))
    updates = updates_received_by(client)

    stream_request.send_event(delta_payload_text(configs: [banner.except("target")]))

    expect(updates.pop(timeout: 5)).to eq(
      ConfigDirector::ConfigsUpdatedEvent.new(keys: [], removed_keys: ["banner"])
    )
    expect(client.evaluate("banner", "in-code").reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
  end

  it "skips a config without an id" do
    client, = streaming_client_initialized_with(full_payload_text(configs: [banner.except("id"), limits]))

    expect(client.evaluate("banner", "in-code").reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("banner"))
  end

  it "skips a config whose id is empty" do
    client, = streaming_client_initialized_with(full_payload_text(configs: [banner.merge("id" => ""), limits]))

    expect(client.evaluate("banner", "in-code").reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("banner"))
  end

  it "skips a config without a key of its own" do
    payload = wire_payload("full", [limits], {})
    payload["configs"]["banner"] = banner.except("key")
    client, = streaming_client_initialized_with(JSON.generate(payload))

    expect(client.evaluate("banner", "in-code").reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("banner"))
  end

  it "skips a config without a type" do
    client, = streaming_client_initialized_with(full_payload_text(configs: [banner.except("type"), limits]))

    expect(client.evaluate("banner", "in-code").reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("banner"))
  end

  it "skips a config whose rules are not a list" do
    checkout = wire_config("checkout", "old-checkout")
    checkout["target"]["rules"] = { "first" => wire_rule_serving("new-checkout", conditions: []) }
    client, = streaming_client_initialized_with(full_payload_text(configs: [checkout, limits]))

    expect(client.evaluate("checkout", "in-code").reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config whose variations are not a list" do
    checkout = wire_config("checkout", "old-checkout").merge("variations" => { "first" => { "id" => "variation-new" } })
    client, = streaming_client_initialized_with(full_payload_text(configs: [checkout, limits]))

    expect(client.evaluate("checkout", "in-code").reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a rule whose conditions are not a list" do
    rule = wire_rule_serving("new-checkout", conditions: { "first" => wire_trait_condition("/plan", "pro") })
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [wire_config("checkout", "old-checkout", rules: [rule]), limits])
    )

    expect(client.evaluate("checkout", "in-code").reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a rule whose rollout shares are not a list" do
    rollout = wire_rollout_to_everyone("new-checkout")
    rollout["percentages"] = { "first" => rollout["percentages"].first }
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [wire_config("checkout", "old-checkout", rules: [rollout]), limits])
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a condition whose target values are not a list" do
    condition = wire_trait_condition("/plan", "pro").merge("targetValues" => "pro")
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_serving_new_checkout_when(condition), limits])
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a rule that is not an object" do
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [wire_config("checkout", "old-checkout", rules: [26]), limits])
    )

    expect(client.evaluate("checkout", "in-code").reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a rule without an id" do
    rule = wire_rule_serving("new-checkout", conditions: []).except("id")
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [wire_config("checkout", "old-checkout", rules: [rule]), limits])
    )

    expect(client.evaluate("checkout", "in-code").reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a condition of a kind it does not know" do
    condition = wire_trait_condition("/plan", "pro").merge("kind" => "schedule")
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_serving_new_checkout_when(condition), limits])
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a condition without an attribute" do
    condition = wire_trait_condition("/plan", "pro").except("attribute")
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_serving_new_checkout_when(condition), limits])
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a condition without an operator" do
    condition = wire_trait_condition("/plan", "pro").except("operator")
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_serving_new_checkout_when(condition), limits])
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a condition without a target type" do
    condition = wire_trait_condition("/plan", "pro").except("targetType")
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_serving_new_checkout_when(condition), limits])
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a segment condition without an operator" do
    client, = streaming_client_initialized_with(
      full_payload_text(
        configs: [checkout_serving_new_checkout_when(wire_segment_condition("beta").except("operator")), limits],
        segments: beta_segment_of_the_pro_plan
      )
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a segment condition without a segment ID" do
    client, = streaming_client_initialized_with(
      full_payload_text(
        configs: [checkout_serving_new_checkout_when(wire_segment_condition("beta").except("segmentId")), limits],
        segments: beta_segment_of_the_pro_plan
      )
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a target value that is an object" do
    condition = wire_trait_condition("/plan", "pro").merge("targetValues" => [{ "plan" => "pro" }])
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_serving_new_checkout_when(condition), limits])
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a target value that is a list" do
    condition = wire_trait_condition("/plan", "pro").merge("targetValues" => [["pro"]])
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_serving_new_checkout_when(condition), limits])
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a target value that is null" do
    condition = wire_trait_condition("/plan", "pro").merge("targetValues" => [nil])
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_serving_new_checkout_when(condition), limits])
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a rollout share without an id" do
    rollout = wire_rollout_to_everyone("new-checkout")
    rollout["percentages"].first.delete("id")
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [wire_config("checkout", "old-checkout", rules: [rollout]), limits])
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "skips a config with a rollout share without a percentage" do
    rollout = wire_rollout_to_everyone("new-checkout")
    rollout["percentages"].first.delete("percentage")
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [wire_config("checkout", "old-checkout", rules: [rollout]), limits])
    )

    expect(client.evaluate("checkout", "in-code", context_on_the_pro_plan).reason).to eq("config-state-missing")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(skipped_config_warning("checkout"))
  end

  it "serves a rollout to the contexts the conditions of its rule hold for" do
    rollout_to_the_pro_plan = wire_rollout_to_everyone("new-checkout").merge(
      "type" => "conditional", "conditions" => [wire_trait_condition("/plan", "pro")]
    )
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [wire_config("checkout", "old-checkout", rules: [rollout_to_the_pro_plan])])
    )

    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("new-checkout")
    expect(client.get_value("checkout", "in-code", context_on_the_team_plan)).to eq("old-checkout")
  end

  it "serves a rollout whose shares it could read" do
    client, = streaming_client_initialized_with(
      full_payload_text(
        configs: [wire_config("checkout", "old-checkout", rules: [wire_rollout_to_everyone("new-checkout")])]
      )
    )

    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("new-checkout")
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "skips a segment without groups with one warning, and its conditions hold for no context" do
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_for_the_beta_segment, limits], segments: { "beta" => {} })
    )

    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("old-checkout")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn)).to eq(
      ["[ConfigDirectorClient] Skipping the segment 'beta', its definition could not be read: " \
       "the segment has no groups"]
    )
  end

  it "skips a segment with a segment condition in a group" do
    client, = streaming_client_initialized_with(
      full_payload_text(
        configs: [checkout_for_the_beta_segment],
        segments: { "beta" => { "groups" => [[wire_segment_condition("staff")]] } }
      )
    )

    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("old-checkout")
    expect(logger.messages_at(:warn)).to eq(
      ["[ConfigDirectorClient] Skipping the segment 'beta', its definition could not be read: " \
       "a condition group of the segment holds attribute conditions only"]
    )
  end

  it "skips a segment with a group that is not a list" do
    client, = streaming_client_initialized_with(
      full_payload_text(
        configs: [checkout_for_the_beta_segment, limits],
        segments: { "beta" => { "groups" => ["pro"] } }
      )
    )

    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("old-checkout")
    expect(client.get_value("limits", 0)).to eql(10)
    expect(logger.messages_at(:warn).length).to eq(1)
    expect(logger.messages_at(:warn).first).to start_with(
      "[ConfigDirectorClient] Skipping the segment 'beta', its definition could not be read: "
    )
  end

  it "drops a segment it held when a delta carries it without groups, and names the configs that use it" do
    client, stream_request = streaming_client_initialized_with(
      full_payload_text(configs: [checkout_for_the_beta_segment, banner], segments: beta_segment_of_the_pro_plan)
    )
    served_before_the_delta = client.get_value("checkout", "in-code", context_on_the_pro_plan)
    updates = updates_received_by(client)

    stream_request.send_event(delta_payload_text(segments: { "beta" => {} }))

    expect(updates.pop(timeout: 5)).to eq(
      ConfigDirector::ConfigsUpdatedEvent.new(keys: ["checkout"], removed_keys: [])
    )
    expect(served_before_the_delta).to eq("new-checkout")
    expect(client.get_value("checkout", "in-code", context_on_the_pro_plan)).to eq("old-checkout")
    expect(logger.messages_at(:warn).length).to eq(1)
  end

  it "returns the configs and segments of one payload to every thread that reads while payloads arrive" do
    client, stream_request = streaming_client_initialized_with(payload_for_the_pro_plan)
    updates = updates_received_by(client)
    context = context_on_the_pro_plan
    payloads_keep_arriving = true
    values_read = Queue.new
    readers = Array.new(8) do
      Thread.new do
        while payloads_keep_arriving
          values_read << client.get_all_configs(context: context).values.map(&:value)
          Thread.pass
        end
      end
    end

    values_of_each_read = []
    100.times do |delivery|
      stream_request.send_event(delivery.even? ? payload_for_the_team_plan : payload_for_the_pro_plan)
      updates.pop(timeout: 5)
      16.times { values_of_each_read << values_read.pop }
    end
    payloads_keep_arriving = false
    readers.each(&:join)
    values_of_each_read << values_read.pop until values_read.empty?

    expect(values_of_each_read.uniq).to contain_exactly(%w[inside-pro banner-of-pro], %w[outside-team banner-of-team])
  end

  it "calls the client_ready handlers once, for the first payload only" do
    client = client_connecting_to(sdk_server.url)
    deliveries = Queue.new
    client.on(:client_ready) { deliveries << :client_ready }
    client.on(:configs_updated) { |_update| deliveries << :configs_updated }
    stream_request = initialize_over_a_stream_carrying(full_payload_text(configs: [banner]), client)

    stream_request.send_event(full_payload_text(configs: [banner]))
    stream_request.send_event(full_payload_text(configs: [banner]))

    expect(Array.new(4) { deliveries.pop(timeout: 5) }).to eq(
      %i[configs_updated client_ready configs_updated configs_updated]
    )
  end

  it "calls a watch for every payload that carries its key, even when the value is the same" do
    client = client_connecting_to(sdk_server.url)
    values_of_the_watch = Queue.new
    client.watch("banner", "in-code") { |value| values_of_the_watch << value }
    stream_request = initialize_over_a_stream_carrying(full_payload_text(configs: [banner]), client)

    stream_request.send_event(full_payload_text(configs: [banner]))

    expect(Array.new(2) { values_of_the_watch.pop(timeout: 5) }).to eq(%w[hidden hidden])
  end

  it "calls a watch registered after init for the next payload" do
    client, stream_request = streaming_client_initialized_with(full_payload_text(configs: [banner]))
    values_of_the_watch = Queue.new
    client.watch("banner", "in-code") { |value| values_of_the_watch << value }

    stream_request.send_event(full_payload_text(configs: [wire_config("banner", "shown")]))

    expect(values_of_the_watch.pop(timeout: 5)).to eq("shown")
  end
end
