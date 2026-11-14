# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      module ConfigEvaluator
        def self.evaluate(config_id, targeting_rules, context, segments)
          a_rollout_was_skipped = false
          in_evaluation_order(targeting_rules.rules).each do |rule|
            served = rule.serve(config_id, context, segments)
            case served
            when ServedValue then return served
            when :rollout_skipped_no_identifier then a_rollout_was_skipped = true
            when :not_matched then nil
            end
          end

          default_targeting_rule_value(targeting_rules, a_rollout_was_skipped)
        end

        def self.in_evaluation_order(rules)
          rules.each_with_index
               .sort_by { |rule, position| [rule.order.nil? ? 1 : 0, rule.order || 0, position] }
               .map(&:first)
        end

        def self.default_targeting_rule_value(targeting_rules, a_rollout_was_skipped)
          ServedValue.new(
            value: targeting_rules.default_value,
            value_id: targeting_rules.default_value_id,
            variation_id: targeting_rules.default_variation_id,
            rollout_share: nil,
            served_by: a_rollout_was_skipped ? :default_targeting_rule_after_skipped_rollout : :default_targeting_rule
          )
        end

        private_class_method :in_evaluation_order, :default_targeting_rule_value
      end
    end
  end
end
