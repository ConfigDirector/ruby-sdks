# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      module TargetingRulesParser
        def self.targeting_rules_defined_by(wire_target)
          Evaluation::TargetingRules.new(
            default_value: Evaluation::ScalarText.of(wire_target["defaultValue"]) || "",
            default_value_id: WireFields.text_or_nil_in(wire_target, "defaultValueId"),
            default_variation_id: WireFields.text_or_nil_in(wire_target, "defaultVariationId"),
            rules: WireFields.objects_listed_in(wire_target, "rules", "the config", "a rule").map do |wire_rule|
              rule_defined_by(wire_rule)
            end
          )
        end

        def self.rule_defined_by(wire_rule)
          rule_id = WireFields.text_required_in(wire_rule, "id", "a rule")
          Evaluation::Rule.new(
            id: rule_id, order: WireFields.whole_number_or_nil_in(wire_rule, "order"),
            type: WireFields.text_or_empty_in(wire_rule, "type"),
            target: WireFields.text_or_empty_in(wire_rule, "target"),
            value: Evaluation::ScalarText.of(wire_rule["value"]),
            value_id: WireFields.text_or_nil_in(wire_rule, "valueId"),
            variation_id: WireFields.text_or_nil_in(wire_rule, "variationId"),
            conditions: conditions_listed_in(wire_rule, rule_id), shares: shares_listed_in(wire_rule, rule_id)
          )
        end

        def self.conditions_listed_in(wire_rule, rule_id)
          wire_conditions = WireFields.objects_listed_in(wire_rule, "conditions", "rule #{rule_id}", "a condition")

          wire_conditions.map { |wire_condition| ConditionParser.condition_defined_by(wire_condition) }
        end

        def self.shares_listed_in(wire_rule, rule_id)
          return nil if wire_rule["percentages"].nil?

          WireFields.list_in(wire_rule, "percentages", "rule #{rule_id}").map do |wire_share|
            share_defined_by(wire_share)
          end
        end

        def self.share_defined_by(wire_share)
          percentage = wire_share.is_a?(Hash) ? wire_share["percentage"] : nil
          unless percentage.is_a?(Integer) || percentage.is_a?(Float)
            raise UnreadableDefinition, "a rollout share has no percentage"
          end

          Evaluation::Share.new(
            id: WireFields.text_required_in(wire_share, "id", "a rollout share"), percentage: percentage.to_f,
            value: Evaluation::ScalarText.of(wire_share["value"]),
            value_id: WireFields.text_or_nil_in(wire_share, "valueId"),
            variation_id: WireFields.text_or_nil_in(wire_share, "variationId")
          )
        end

        private_class_method :rule_defined_by, :conditions_listed_in, :shares_listed_in, :share_defined_by
      end
    end
  end
end
