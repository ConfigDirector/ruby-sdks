# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      ConfigRead = Data.define(:config_key, :in_code_default_value, :context)

      class ConfigRead
        def in_code_default_evaluation(reason)
          ConfigEvaluation.new(
            key: config_key, value: in_code_default_value.value, default_value: true, reason: reason, context: context
          )
        end

        def served_evaluation(typed_value, state, reason)
          ConfigEvaluation.new(
            key: config_key, value: typed_value.value, default_value: false, reason: reason,
            value_id: state.value_id, variation: state.variation, context: context
          )
        end
      end
    end
  end
end
