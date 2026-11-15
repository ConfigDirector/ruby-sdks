# frozen_string_literal: true

require "json"

module WirePayloads
  ENVIRONMENT_ID = "3f0e6a52-8c1d-4b7e-9a2f-5d4c1e7b6a90"
  PROJECT_ID = "b81d4c07-2e6f-4a39-8d15-0c9e7f3a2b64"

  def full_payload_text(configs: [], segments: {})
    JSON.generate(wire_payload("full", configs, segments))
  end

  def delta_payload_text(configs: [], segments: {})
    JSON.generate(wire_payload("delta", configs, segments))
  end

  def wire_payload(kind, configs, segments)
    {
      "payloadVersion" => 1, "environmentId" => ENVIRONMENT_ID, "projectId" => PROJECT_ID, "kind" => kind,
      "timestamp" => "2026-11-14T09:30:00.000Z",
      "configs" => configs.to_h { |wire_config| [wire_config.fetch("key"), wire_config] },
      "segments" => segments
    }
  end

  def wire_config(key, default_targeting_rule_value, type: "string", rules: [], variations: [])
    {
      "id" => "id-of-#{key}", "key" => key, "type" => type, "typeConstraints" => nil, "variations" => variations,
      "target" => {
        "environmentId" => ENVIRONMENT_ID, "rules" => rules, "defaultValue" => default_targeting_rule_value,
        "defaultValueId" => "value-id-of-#{key}"
      }
    }
  end

  def wire_rule_serving(value, conditions:)
    {
      "id" => "rule-serving-#{value}", "order" => 0, "type" => "conditional", "target" => "value",
      "value" => value, "valueId" => "value-id-of-#{value}", "conditions" => conditions, "percentages" => []
    }
  end

  def wire_rollout_to_everyone(value)
    {
      "id" => "rollout-of-#{value}", "order" => 0, "type" => "percentage", "target" => "percentage",
      "conditions" => [],
      "percentages" => [{ "id" => "share-of-#{value}", "percentage" => 100, "value" => value }]
    }
  end

  def wire_trait_condition(trait_pointer, text)
    {
      "id" => "condition-on-#{trait_pointer}", "kind" => "attribute", "attribute" => "traits",
      "trait" => trait_pointer, "operator" => "equals", "targetType" => "text", "targetValues" => [text]
    }
  end

  def wire_segment_condition(segment_id)
    { "id" => "condition-on-#{segment_id}", "kind" => "segment", "operator" => "in", "segmentId" => segment_id }
  end

  def wire_segment_of_contexts_with_trait(trait_pointer, text)
    { "groups" => [[wire_trait_condition(trait_pointer, text)]] }
  end
end
