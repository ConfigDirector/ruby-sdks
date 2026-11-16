# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      ConfigRead = Data.define(:config_key, :in_code_default_value, :context)

      class ConfigRead
        def evaluated_to_the_in_code_default_value(reason, config_state)
          EvaluatedRead.new(
            config_read: self, config_state: config_state,
            evaluation: ConfigEvaluation.new(
              key: config_key, value: in_code_default_value.value, default_value: true, reason: reason,
              context: context
            )
          )
        end

        def evaluated_to(typed_value, config_state, reason)
          EvaluatedRead.new(
            config_read: self, config_state: config_state,
            evaluation: ConfigEvaluation.new(
              key: config_key, value: typed_value.value, default_value: false, reason: reason,
              value_id: config_state.value_id, variation: config_state.variation, context: context
            )
          )
        end
      end
    end
  end
end
