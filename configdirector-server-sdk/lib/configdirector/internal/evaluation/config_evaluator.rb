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

          targeting_rules.default_targeting_rule_value(a_rollout_was_skipped: a_rollout_was_skipped)
        end

        def self.in_evaluation_order(rules)
          rules.sort_by.with_index { |rule, position| [rule.order || Float::INFINITY, position] }
        end

        private_class_method :in_evaluation_order
      end
    end
  end
end
