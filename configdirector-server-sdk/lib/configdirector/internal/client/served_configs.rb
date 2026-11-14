# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      ServedConfigs = Data.define(:payload, :metadata)

      class ServedConfigs
        REASON_BY_SERVED_BY = {
          matching_rule: "found-match",
          default_targeting_rule: "found-match",
          default_targeting_rule_after_skipped_rollout: "rollout-skipped-no-identifier"
        }.freeze

        private_constant :REASON_BY_SERVED_BY

        def evaluation(config_read)
          definition = payload.configs[config_read.config_key]
          return config_read.in_code_default_evaluation("config-state-missing") if definition.nil?

          evaluation_of(definition, config_read)
        end

        def update_since(replaced_configs)
          ConfigsUpdatedEvent.new(keys: config_keys, removed_keys: Array(replaced_configs&.config_keys) - config_keys)
        end

        def states(context, config_keys)
          payload.configs
                 .select { |config_key, _definition| config_keys.nil? || config_keys.include?(config_key) }
                 .transform_values { |definition| definition.state_serving(value_served_to(context, definition)) }
        end

        protected

        def config_keys
          payload.configs.keys
        end

        private

        def evaluation_of(definition, config_read)
          served = value_served_to(config_read.context, definition)
          state = definition.state_serving(served)
          typed_value_or_reason = Value::ServedText.typed_as(
            config_read.in_code_default_value.kind, state.value, state.type
          )

          case typed_value_or_reason
          when Value::TypedValue
            config_read.served_evaluation(typed_value_or_reason, state, REASON_BY_SERVED_BY.fetch(served.served_by))
          else config_read.in_code_default_evaluation(typed_value_or_reason)
          end
        end

        def value_served_to(context, definition)
          Evaluation::ConfigEvaluator.evaluate(
            definition.id, definition.targeting_rules, evaluation_context_of(context), payload.segments
          )
        end

        def evaluation_context_of(context)
          Evaluation::EvaluationContext.new(
            identifier: context&.id, kind: context&.kind, name: context&.name, traits: context&.traits || {},
            app_name: metadata.app_name, app_version: metadata.app_version
          )
        end
      end
    end
  end
end
