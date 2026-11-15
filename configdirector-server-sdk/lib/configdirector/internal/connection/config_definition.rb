# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      ConfigDefinition = Data.define(:id, :key, :type, :targeting_rules, :variations)

      class ConfigDefinition
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
