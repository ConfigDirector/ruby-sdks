# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      ConfigDefinition = Data.define(:id, :key, :type, :targeting_rules, :variations)

      class ConfigDefinition
        def self.serving_each_value_to_every_context(values, id_prefix)
          Value::NativeValues.config_keys_of(values).zip(values.values).to_h do |config_key, value|
            encoded_value = Value::EncodedNativeValue.of(value, config_key)
            targeting_rules = Evaluation::TargetingRules.new(
              default_value: encoded_value.served_text, default_value_id: nil, default_variation_id: nil, rules: []
            )

            [config_key, new(id: "#{id_prefix}#{config_key}", key: config_key, type: encoded_value.config_type,
                             targeting_rules: targeting_rules, variations: [])]
          end
        end

        def uses_any_segment_of?(segment_ids)
          targeting_rules.rules.any? { |rule| rule.uses_any_segment_of?(segment_ids) }
        end

        def state_serving(served)
          rollout_share = served.rollout_share

          ConfigState.new(
            id: id, key: key, type: type, value: served.value, value_id: served.value_id,
            variation: variations.find { |variation| variation.id == served.variation_id },
            rule_id: rollout_share&.rule_id, share_id: rollout_share&.share_id
          )
        end
      end
    end
  end
end
