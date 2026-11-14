# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Evaluation::ConfigEvaluator do
  segment = ConfigDirector::Internal::Evaluation::Segment
  segment_condition = ConfigDirector::Internal::Evaluation::SegmentCondition
  attribute_condition = ConfigDirector::Internal::Evaluation::AttributeCondition
  served_value = ConfigDirector::Internal::Evaluation::ServedValue
  rollout_share = ConfigDirector::Internal::Evaluation::RolloutShare
  targeting_rules = ConfigDirector::Internal::Evaluation::TargetingRules
  contract_config_id = "11111111-1111-4111-8111-111111111111"
  acme_segment_id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

  context_with = lambda do |**fields|
    ConfigDirector::Internal::Evaluation::EvaluationContext.new(
      identifier: nil, kind: nil, name: nil, traits: {}, app_name: nil, app_version: nil, **fields
    )
  end
  rule_with = lambda do |**fields|
    ConfigDirector::Internal::Evaluation::Rule.new(
      value: nil, value_id: nil, variation_id: nil, conditions: [], shares: nil, **fields
    )
  end
  share_with = lambda do |**fields|
    ConfigDirector::Internal::Evaluation::Share.new(value_id: nil, variation_id: nil, **fields)
  end
  evaluate = lambda do |rules, context, segments: {}, default_variation_id: nil|
    described_class.evaluate(
      contract_config_id,
      targeting_rules.new(
        default_value: "NONE", default_value_id: "default-value", default_variation_id: default_variation_id,
        rules: rules
      ),
      context,
      segments
    )
  end
  value_rule = lambda do |id, order, value, *conditions|
    rule_with.call(
      id: id, order: order, type: "conditional", target: "value", value: value, value_id: "#{id}-value",
      conditions: conditions
    )
  end
  percentage_rule = lambda do |*shares|
    rule_with.call(id: "rollout", order: 0, type: "percentage", target: "percentage", shares: shares)
  end
  share_of = lambda do |id, percentage, value|
    share_with.call(id: id, percentage: percentage, value: value, value_id: "#{id}-value")
  end
  identifier_is = lambda do |identifier|
    attribute_condition.new(
      attribute: "identifier", trait: nil, operator: "equals", target_type: "text", target_values: [identifier]
    )
  end
  plan_is = lambda do |plan|
    attribute_condition.new(
      attribute: "traits", trait: "/plan", operator: "equals", target_type: "text", target_values: [plan]
    )
  end
  acme_employees = {
    acme_segment_id => segment.new(
      condition_groups: [[
        attribute_condition.new(
          attribute: "traits", trait: "/email", operator: "ends with any of", target_type: "text",
          target_values: ["@acme.com"]
        )
      ]]
    )
  }

  it "serves the default targeting rule value for a config without rules" do
    served = evaluate.call([], context_with.call(identifier: "u1"))

    expect(served).to eq(
      served_value.new(
        value: "NONE", value_id: "default-value", variation_id: nil, rollout_share: nil,
        served_by: :default_targeting_rule
      )
    )
  end

  it "serves the value of the first rule that applies" do
    rules = [
      value_rule.call("first", 0, "A", identifier_is.call("u2")),
      value_rule.call("second", 1, "B", identifier_is.call("u1")),
      value_rule.call("third", 2, "C", identifier_is.call("u1"))
    ]

    served = evaluate.call(rules, context_with.call(identifier: "u1"))

    expect(served).to eq(
      served_value.new(
        value: "B", value_id: "second-value", variation_id: nil, rollout_share: nil, served_by: :matching_rule
      )
    )
  end

  it "tries rules in ascending order regardless of their position" do
    rules = [value_rule.call("listed-first", 1, "B"), value_rule.call("listed-second", 0, "A")]

    served = evaluate.call(rules, context_with.call(identifier: "u1"))

    expect(served.value).to eq("A")
  end

  it "tries rules without an order after every ordered rule" do
    rules = [value_rule.call("unordered", nil, "C"), value_rule.call("ordered", 5, "A")]

    served = evaluate.call(rules, context_with.call(identifier: "u1"))

    expect(served.value).to eq("A")
  end

  it "keeps rules without an order in the order listed" do
    rules = Array.new(20) { |position| value_rule.call("unordered-#{position}", nil, "listed-#{position}") }

    served = evaluate.call(rules, context_with.call(identifier: "u1"))

    expect(served.value).to eq("listed-0")
  end

  it "serves the default targeting rule value when no rule applies" do
    rules = [value_rule.call("only", 0, "A", identifier_is.call("u2"))]

    served = evaluate.call(rules, context_with.call(identifier: "u1"))

    expect(served).to eq(
      served_value.new(
        value: "NONE", value_id: "default-value", variation_id: nil, rollout_share: nil,
        served_by: :default_targeting_rule
      )
    )
  end

  it "applies a conditional rule when every condition holds" do
    rules = [value_rule.call("both", 0, "A", identifier_is.call("u1"), plan_is.call("pro"))]

    served = evaluate.call(rules, context_with.call(identifier: "u1", traits: { "plan" => "pro" }))

    expect(served.served_by).to eq(:matching_rule)
  end

  it "does not apply a conditional rule when one condition fails" do
    rules = [value_rule.call("both", 0, "A", identifier_is.call("u1"), plan_is.call("pro"))]

    served = evaluate.call(rules, context_with.call(identifier: "u1", traits: { "plan" => "free" }))

    expect(served.served_by).to eq(:default_targeting_rule)
  end

  it "applies a rule without conditions to every context" do
    served = evaluate.call([value_rule.call("everyone", 0, "A")], context_with.call)

    expect(served.value).to eq("A")
  end

  it "applies a rule with an in segment condition to a context in the segment" do
    rules = [value_rule.call("acme", 0, "A", segment_condition.new(operator: "in", segment_id: acme_segment_id))]

    served = evaluate.call(
      rules, context_with.call(traits: { "email" => "ann@acme.com" }), segments: acme_employees
    )

    expect(served.value).to eq("A")
  end

  it "applies a rule with a not in segment condition to a context outside the segment" do
    rules = [
      value_rule.call("not-acme", 0, "A", segment_condition.new(operator: "not in", segment_id: acme_segment_id))
    ]

    served = evaluate.call(
      rules, context_with.call(traits: { "email" => "bob@example.com" }), segments: acme_employees
    )

    expect(served.value).to eq("A")
  end

  it "combines a segment condition with an attribute condition by AND" do
    rules = [
      value_rule.call(
        "acme-pro", 0, "A", segment_condition.new(operator: "in", segment_id: acme_segment_id), plan_is.call("pro")
      )
    ]

    served = evaluate.call(
      rules, context_with.call(traits: { "email" => "ann@acme.com", "plan" => "free" }), segments: acme_employees
    )

    expect(served.value).to eq("NONE")
  end

  it "falls through a rule with a segment condition when the payload has no segments" do
    rules = [
      value_rule.call("not-acme", 0, "A", segment_condition.new(operator: "not in", segment_id: acme_segment_id)),
      value_rule.call("next", 1, "B")
    ]

    served = evaluate.call(rules, context_with.call(traits: { "email" => "bob@example.com" }))

    expect(served.value).to eq("B")
  end

  it "skips a rule of an unknown type" do
    rules = [
      rule_with.call(id: "unknown", order: 0, type: "schedule", target: "value", value: "A", value_id: "unknown-value"),
      value_rule.call("known", 1, "B")
    ]

    served = evaluate.call(rules, context_with.call)

    expect(served.value).to eq("B")
  end

  it "skips a conditional rule with an unknown target" do
    rules = [
      rule_with.call(
        id: "unknown", order: 0, type: "conditional", target: "variation", value: "A", value_id: "unknown-value"
      ),
      value_rule.call("known", 1, "B")
    ]

    served = evaluate.call(rules, context_with.call)

    expect(served.value).to eq("B")
  end

  it "skips a rule serving a value without a value" do
    rules = [
      rule_with.call(id: "valueless", order: 0, type: "conditional", target: "value", value: nil),
      value_rule.call("next", 1, "B")
    ]

    served = evaluate.call(rules, context_with.call)

    expect(served.value).to eq("B")
  end

  it "reports the variation and no rollout share of a rule serving a single value" do
    rules = [
      rule_with.call(
        id: "only", order: 0, type: "conditional", target: "value", value: "A", value_id: "only-value",
        variation_id: "treatment"
      )
    ]

    served = evaluate.call(rules, context_with.call)

    expect(served).to eq(
      served_value.new(
        value: "A", value_id: "only-value", variation_id: "treatment", rollout_share: nil, served_by: :matching_rule
      )
    )
  end

  it "reports the variation of the default targeting rule value" do
    served = evaluate.call([], context_with.call(identifier: "u1"), default_variation_id: "control")

    expect(served).to eq(
      served_value.new(
        value: "NONE", value_id: "default-value", variation_id: "control", rollout_share: nil,
        served_by: :default_targeting_rule
      )
    )
  end

  it "serves a percentage rollout from a conditional rule" do
    rules = [
      rule_with.call(
        id: "rollout", order: 0, type: "conditional", target: "percentage", conditions: [identifier_is.call("u582")],
        shares: [share_of.call("b0", 50.0, "0"), share_of.call("b1", 50.0, "1")]
      )
    ]

    served = evaluate.call(rules, context_with.call(identifier: "u582"))

    expect(served).to eq(
      served_value.new(
        value: "1", value_id: "b1-value", variation_id: nil,
        rollout_share: rollout_share.new(rule_id: "rollout", share_id: "b1"), served_by: :matching_rule
      )
    )
  end

  it "gives a context on a share boundary the share that starts there" do
    rules = [percentage_rule.call(share_of.call("b0", 50.0, "0"), share_of.call("b1", 50.0, "1"))]

    served = evaluate.call(rules, context_with.call(identifier: "u582"))

    expect(served).to eq(
      served_value.new(
        value: "1", value_id: "b1-value", variation_id: nil,
        rollout_share: rollout_share.new(rule_id: "rollout", share_id: "b1"), served_by: :matching_rule
      )
    )
  end

  it "gives a context just below a share boundary the share that ends there" do
    rules = [percentage_rule.call(share_of.call("b0", 50.0, "0"), share_of.call("b1", 50.0, "1"))]

    served = evaluate.call(rules, context_with.call(identifier: "u4331"))

    expect(served.value).to eq("0")
  end

  it "serves nobody from a zero-width share on a boundary" do
    rules = [
      percentage_rule.call(
        share_of.call("b0", 50.0, "0"), share_of.call("b1", 0.0, "1"), share_of.call("b2", 50.0, "2")
      )
    ]

    served = evaluate.call(rules, context_with.call(identifier: "u582"))

    expect(served.value).to eq("2")
  end

  it "serves nobody from a leading zero-width share" do
    rules = [percentage_rule.call(share_of.call("b0", 0.0, "0"), share_of.call("b1", 100.0, "1"))]

    served = evaluate.call(rules, context_with.call(identifier: "user-1"))

    expect(served.value).to eq("1")
  end

  it "reports the rule, share and variation of a rollout" do
    rules = [
      percentage_rule.call(
        share_of.call("b0", 50.0, "0"),
        share_with.call(id: "b1", percentage: 50.0, value: "1", value_id: "b1-value", variation_id: "treatment")
      )
    ]

    served = evaluate.call(rules, context_with.call(identifier: "u582"))

    expect(served).to eq(
      served_value.new(
        value: "1", value_id: "b1-value", variation_id: "treatment",
        rollout_share: rollout_share.new(rule_id: "rollout", share_id: "b1"), served_by: :matching_rule
      )
    )
  end

  it "lands a user in the share its identifier hashes to" do
    rules = [percentage_rule.call(share_of.call("b0", 50.0, "0"), share_of.call("b1", 50.0, "1"))]

    served = evaluate.call(rules, context_with.call(identifier: "user-1"))

    expect(served.value).to eq("0")
  end

  it "can land a device with the same identifier as a user in another share" do
    rules = [percentage_rule.call(share_of.call("b0", 50.0, "0"), share_of.call("b1", 50.0, "1"))]

    served = evaluate.call(rules, context_with.call(identifier: "user-1", kind: "device"))

    expect(served.value).to eq("1")
  end

  it "lands an explicit user kind where an omitted kind lands" do
    rules = [percentage_rule.call(share_of.call("b0", 50.0, "0"), share_of.call("b1", 50.0, "1"))]

    served = evaluate.call(rules, context_with.call(identifier: "user-1", kind: "user"))

    expect(served.value).to eq("0")
  end

  it "still buckets an empty identifier" do
    rules = [percentage_rule.call(share_of.call("b0", 50.0, "0"), share_of.call("b1", 50.0, "1"))]

    served = evaluate.call(rules, context_with.call(identifier: ""))

    expect(served.value).to eq("1")
  end

  it "serves the default targeting rule value when the shares do not cover the context" do
    rules = [percentage_rule.call(share_of.call("b0", 10.0, "0"), share_of.call("b1", 10.0, "1"))]

    served = evaluate.call(rules, context_with.call(identifier: "u582"))

    expect(served).to eq(
      served_value.new(
        value: "NONE", value_id: "default-value", variation_id: nil, rollout_share: nil,
        served_by: :default_targeting_rule
      )
    )
  end

  it "falls through a rollout covering nobody to the next rule" do
    rules = [percentage_rule.call(share_of.call("b0", 0.0, "0")), value_rule.call("next", 1, "B")]

    served = evaluate.call(rules, context_with.call(identifier: "u582"))

    expect(served.value).to eq("B")
  end

  it "falls through a share without a value to the next rule" do
    rules = [
      percentage_rule.call(share_with.call(id: "b0", percentage: 100.0, value: nil)),
      value_rule.call("next", 1, "B")
    ]

    served = evaluate.call(rules, context_with.call(identifier: "u582"))

    expect(served.value).to eq("B")
  end

  it "skips the rollout for a context without an identifier" do
    rules = [
      percentage_rule.call(
        share_of.call("b0", 0.0, "0"), share_of.call("b1", 10.0, "1"), share_of.call("b2", 90.0, "2")
      )
    ]

    served = evaluate.call(rules, context_with.call)

    expect(served).to eq(
      served_value.new(
        value: "NONE", value_id: "default-value", variation_id: nil, rollout_share: nil,
        served_by: :default_targeting_rule_after_skipped_rollout
      )
    )
  end

  it "skips the rollout for a device without an identifier too" do
    rules = [
      percentage_rule.call(
        share_of.call("b0", 0.0, "0"), share_of.call("b1", 10.0, "1"), share_of.call("b2", 90.0, "2")
      )
    ]

    served = evaluate.call(rules, context_with.call(kind: "device"))

    expect(served).to eq(
      served_value.new(
        value: "NONE", value_id: "default-value", variation_id: nil, rollout_share: nil,
        served_by: :default_targeting_rule_after_skipped_rollout
      )
    )
  end

  it "reports the variation of the default targeting rule value after a skipped rollout" do
    rules = [percentage_rule.call(share_of.call("b0", 100.0, "0"))]

    served = evaluate.call(rules, context_with.call, default_variation_id: "control")

    expect(served).to eq(
      served_value.new(
        value: "NONE", value_id: "default-value", variation_id: "control", rollout_share: nil,
        served_by: :default_targeting_rule_after_skipped_rollout
      )
    )
  end

  it "serves a context without an identifier from the rule after a skipped rollout" do
    rules = [percentage_rule.call(share_of.call("b0", 100.0, "0")), value_rule.call("next", 1, "B")]

    served = evaluate.call(rules, context_with.call)

    expect(served).to eq(
      served_value.new(
        value: "B", value_id: "next-value", variation_id: nil, rollout_share: nil, served_by: :matching_rule
      )
    )
  end

  it "serves a context without an identifier matching a conditional rollout from a later rule on the app version" do
    rules = [
      rule_with.call(
        id: "rollout", order: 0, type: "conditional", target: "percentage", conditions: [plan_is.call("pro")],
        shares: [share_of.call("b0", 100.0, "0")]
      ),
      value_rule.call(
        "version-2", 1, "B",
        attribute_condition.new(
          attribute: "appVersion", trait: nil, operator: ">=", target_type: "semver", target_values: ["2.0.0"]
        )
      )
    ]

    served = evaluate.call(rules, context_with.call(traits: { "plan" => "pro" }, app_version: "2.1.0"))

    expect(served).to eq(
      served_value.new(
        value: "B", value_id: "version-2-value", variation_id: nil, rollout_share: nil, served_by: :matching_rule
      )
    )
  end

  it "serves the default targeting rule value after a skipped rollout when no later rule matches" do
    rules = [
      percentage_rule.call(share_of.call("b0", 100.0, "0")),
      value_rule.call("next", 1, "B", plan_is.call("pro"))
    ]

    served = evaluate.call(rules, context_with.call(traits: { "plan" => "free" }))

    expect(served.served_by).to eq(:default_targeting_rule_after_skipped_rollout)
  end

  it "still serves a context without an identifier from a rule before the rollout" do
    rules = [
      rule_with.call(
        id: "rollout", order: 1, type: "percentage", target: "percentage", shares: [share_of.call("b0", 100.0, "0")]
      ),
      value_rule.call("first", 0, "A")
    ]

    served = evaluate.call(rules, context_with.call)

    expect(served).to eq(
      served_value.new(
        value: "A", value_id: "first-value", variation_id: nil, rollout_share: nil, served_by: :matching_rule
      )
    )
  end

  it "skips a conditional rollout whose conditions hold for a context without an identifier" do
    rules = [
      rule_with.call(
        id: "rollout", order: 0, type: "conditional", target: "percentage", conditions: [plan_is.call("pro")],
        shares: [share_of.call("b0", 100.0, "0")]
      )
    ]

    served = evaluate.call(rules, context_with.call(traits: { "plan" => "pro" }))

    expect(served.served_by).to eq(:default_targeting_rule_after_skipped_rollout)
  end

  it "does not skip a conditional rollout whose conditions fail for a context without an identifier" do
    rules = [
      rule_with.call(
        id: "rollout", order: 0, type: "conditional", target: "percentage", conditions: [plan_is.call("pro")],
        shares: [share_of.call("b0", 100.0, "0")]
      )
    ]

    served = evaluate.call(rules, context_with.call(traits: { "plan" => "free" }))

    expect(served.served_by).to eq(:default_targeting_rule)
  end

  it "does not skip a rollout without a share list for a context without an identifier" do
    rules = [rule_with.call(id: "rollout", order: 0, type: "percentage", target: "percentage")]

    served = evaluate.call(rules, context_with.call)

    expect(served.served_by).to eq(:default_targeting_rule)
  end

  it "skips a rollout with an empty share list for a context without an identifier" do
    rules = [percentage_rule.call]

    served = evaluate.call(rules, context_with.call)

    expect(served.served_by).to eq(:default_targeting_rule_after_skipped_rollout)
  end

  it "falls through a rollout with an empty share list for a context with an identifier" do
    rules = [percentage_rule.call, value_rule.call("next", 1, "B")]

    served = evaluate.call(rules, context_with.call(identifier: "u1"))

    expect(served.value).to eq("B")
  end
end
