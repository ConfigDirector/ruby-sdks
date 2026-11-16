# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      ReportedEvaluation = Data.define(
        :config_read, :config_state, :returned_the_in_code_default_value, :reason, :value_kept_for_the_report
      )

      class ReportedEvaluation
        REQUESTED_TYPE_BY_IN_CODE_DEFAULT_VALUE_KIND = {
          boolean: "Boolean",
          string: "String",
          integer: "Integer",
          float: "Float",
          json_object: "Hash",
          json_array: "Array"
        }.freeze

        private_constant :REQUESTED_TYPE_BY_IN_CODE_DEFAULT_VALUE_KIND

        def self.of(evaluated_read)
          evaluation = evaluated_read.evaluation
          config_state = evaluated_read.config_state
          reported_by_the_value_id_sent_with_it = ReportedValue.reported_by_the_value_id_sent_with_it?(
            evaluation.value, config_state&.type, evaluation.value_id
          )

          new(
            config_read: evaluated_read.config_read, config_state: config_state,
            returned_the_in_code_default_value: evaluation.default_value?, reason: evaluation.reason,
            value_kept_for_the_report: reported_by_the_value_id_sent_with_it ? nil : evaluation.value
          )
        end

        def wire_event
          wire_context.merge(wire_evaluation, wire_identifiers_of_what_was_served).compact
        end

        private

        def wire_context
          reported_context = ReportedContext.of(config_read.context)

          { contextId: reported_context&.identifier, contextKind: reported_context&.kind }
        end

        def wire_evaluation
          in_code_default_value = config_read.in_code_default_value

          {
            key: config_read.config_key.to_s, type: config_state&.type,
            defaultValue: ReportedValue.of(in_code_default_value.value, config_state&.type),
            requestedType: REQUESTED_TYPE_BY_IN_CODE_DEFAULT_VALUE_KIND.fetch(in_code_default_value.kind),
            evaluatedValue: wire_evaluated_value, usedDefault: returned_the_in_code_default_value,
            evaluationReason: reason
          }
        end

        def wire_evaluated_value
          value_kept = value_kept_for_the_report
          return { valueId: config_state_served&.value_id } if value_kept.nil?

          ReportedValue.of(value_kept, config_state&.type)
        end

        def wire_identifiers_of_what_was_served
          served = config_state_served

          {
            evaluatedValueId: served&.value_id, ruleId: served&.rule_id, shareId: served&.share_id,
            variationId: served&.variation&.id
          }
        end

        def config_state_served
          returned_the_in_code_default_value ? nil : config_state
        end
      end
    end
  end
end
