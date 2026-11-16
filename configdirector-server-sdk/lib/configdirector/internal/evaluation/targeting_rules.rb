# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      TargetingRules = Data.define(:default_value, :default_value_id, :default_variation_id, :rules)

      class TargetingRules
        def default_targeting_rule_value(a_rollout_was_skipped:)
          ServedValue.new(
            value: default_value, value_id: default_value_id, variation_id: default_variation_id, rollout_share: nil,
            served_by: a_rollout_was_skipped ? :default_targeting_rule_after_skipped_rollout : :default_targeting_rule
          )
        end
      end
    end
  end
end
