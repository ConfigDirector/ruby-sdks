# frozen_string_literal: true

require "json"

module FiveStandardConfigs
  ENVIRONMENT_ID = "3f0e6a52-8c1d-4b7e-9a2f-5d4c1e7b6a90"

  def self.wire_config(key, id:, type:, default_value:, rules: [])
    {
      "id" => id, "key" => key, "type" => type, "typeConstraints" => nil, "variations" => [],
      "target" => {
        "environmentId" => ENVIRONMENT_ID, "rules" => rules, "defaultValue" => default_value,
        "defaultValueId" => "value-of-#{key}"
      }
    }
  end

  WIRE_CONFIGS = [
    wire_config(
      "temporary-feature-flag",
      id: "7b0c4f52-3d1e-4a86-9c2f-1e5d8a6b4c01", type: "boolean", default_value: "false",
      rules: [{
        "id" => "rule-flag-rollout", "order" => 0, "type" => "percentage", "target" => "percentage",
        "conditions" => [],
        "percentages" => [{ "id" => "share-flag-on", "percentage" => 100, "value" => "true" }]
      }]
    ),
    wire_config(
      "permanent-kill-switch", id: "2f6d1c3e-8a47-4b55-9d0e-6c1f7a9b2e02", type: "boolean", default_value: "true"
    ),
    wire_config("integer-config", id: "9a3e5b71-6c2d-4f08-8b1a-4d7c2e9f5a03", type: "integer", default_value: "42"),
    wire_config(
      "day-of-the-week-config",
      id: "5c8a2d94-1b7f-4e63-a0d5-9f3b6c1e7d04", type: "string", default_value: "Monday",
      rules: [{
        "id" => "rule-pro-plan", "order" => 0, "type" => "conditional", "target" => "value", "value" => "Tuesday",
        "percentages" => [],
        "conditions" => [{
          "id" => "condition-pro-plan", "kind" => "attribute", "attribute" => "traits", "trait" => "/plan",
          "operator" => "equals", "targetType" => "text", "targetValues" => ["pro"]
        }]
      }]
    ),
    wire_config(
      "json-value-config",
      id: "e1d7f3a6-4c9b-4d21-b8e0-2a6f5c3d9b05", type: "json", default_value: '{"greeting":"hello","sizes":[1,2]}'
    )
  ].freeze

  PAYLOAD_TEXT = JSON.generate(
    "payloadVersion" => 1, "environmentId" => ENVIRONMENT_ID, "projectId" => "b81d4c07-2e6f-4a39-8d15-0c9e7f3a2b64",
    "kind" => "full", "timestamp" => "2026-11-14T09:30:00.000Z",
    "configs" => WIRE_CONFIGS.to_h { |wire_config| [wire_config.fetch("key"), wire_config] },
    "segments" => {}
  )
end
