# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      class HardCodedConnection
        def open
          yield ServerSdkPayload.new(configs: CONFIG_DEFINITIONS.to_h { |definition| [definition.key, definition] },
                                     segments: {})
        end

        def close; end

        def self.serving(default_targeting_rule_value, value_id, variation_id = nil, rules: [])
          Evaluation::TargetingRules.new(
            default_value: default_targeting_rule_value, default_value_id: value_id,
            default_variation_id: variation_id, rules: rules
          )
        end

        def self.value_when(condition, value, rule_id:, value_id:)
          Evaluation::Rule.new(
            id: rule_id, order: 0, type: "conditional", target: "value", value: value, value_id: value_id,
            variation_id: nil, conditions: [condition], shares: nil
          )
        end

        def self.rollout_to_everyone(value, rule_id:, share_id:, value_id:, variation_id:)
          Evaluation::Rule.new(
            id: rule_id, order: 0, type: "percentage", target: "percentage", value: nil, value_id: nil,
            variation_id: nil, conditions: [],
            shares: [Evaluation::Share.new(id: share_id, percentage: 100.0, value: value, value_id: value_id,
                                           variation_id: variation_id)]
          )
        end

        private_class_method :serving, :value_when, :rollout_to_everyone

        CONFIG_DEFINITIONS = [
          ConfigDefinition.new(
            id: "7b0c4f52-3d1e-4a86-9c2f-1e5d8a6b4c01", key: "temporary-feature-flag", type: "boolean",
            targeting_rules: serving(
              "false", "value-flag-off", "variation-flag-off",
              rules: [rollout_to_everyone("true", rule_id: "rule-flag-rollout", share_id: "share-flag-on",
                                                  value_id: "value-flag-on", variation_id: "variation-flag-on")]
            ),
            variations: [Variation.new(id: "variation-flag-on", name: "On"),
                         Variation.new(id: "variation-flag-off", name: "Off")]
          ),
          ConfigDefinition.new(
            id: "2f6d1c3e-8a47-4b55-9d0e-6c1f7a9b2e02", key: "permanent-kill-switch", type: "boolean",
            targeting_rules: serving("true", "value-kill-switch-on"), variations: []
          ),
          ConfigDefinition.new(
            id: "9a3e5b71-6c2d-4f08-8b1a-4d7c2e9f5a03", key: "integer-config", type: "integer",
            targeting_rules: serving(
              "42", "value-integer-42",
              rules: [value_when(
                Evaluation::AttributeCondition.new(attribute: "appName", trait: nil, operator: "equals",
                                                   target_type: "text", target_values: ["beta-app"]),
                "7", rule_id: "rule-beta-app", value_id: "value-integer-7"
              )]
            ),
            variations: []
          ),
          ConfigDefinition.new(
            id: "5c8a2d94-1b7f-4e63-a0d5-9f3b6c1e7d04", key: "day-of-the-week-config", type: "string",
            targeting_rules: serving(
              "Monday", "value-monday",
              rules: [value_when(
                Evaluation::AttributeCondition.new(attribute: "traits", trait: "/plan", operator: "equals",
                                                   target_type: "text", target_values: ["pro"]),
                "Tuesday", rule_id: "rule-pro-plan", value_id: "value-tuesday"
              )]
            ),
            variations: []
          ),
          ConfigDefinition.new(
            id: "e1d7f3a6-4c9b-4d21-b8e0-2a6f5c3d9b05", key: "json-value-config", type: "json",
            targeting_rules: serving('{"greeting":"hello","sizes":[1,2]}', "value-json-greeting"), variations: []
          ),
          ConfigDefinition.new(
            id: "0a4c9e27-5d83-4f16-b7a2-6e1d3c8f9b09", key: "json-list-config", type: "json",
            targeting_rules: serving('["small","large"]', "value-json-sizes"), variations: []
          ),
          ConfigDefinition.new(
            id: "4b9e6c18-7f3a-4c52-9e1d-8c0a7b2f6e06", key: "float-config", type: "float",
            targeting_rules: serving("26.0", "value-float-26"), variations: []
          ),
          ConfigDefinition.new(
            id: "c6a1e8d3-2b5f-4937-a4c8-3e9d1f7b0a07", key: "config-without-a-value", type: "string",
            targeting_rules: serving("", nil), variations: []
          ),
          ConfigDefinition.new(
            id: "8d2f7a45-9e6c-4b10-8f3e-5b1c4d6a2e08", key: "malformed-json-config", type: "json",
            targeting_rules: serving('{"greeting":', "value-malformed-json"), variations: []
          )
        ].freeze

        private_constant :CONFIG_DEFINITIONS
      end
    end
  end
end
