# frozen_string_literal: true

module ConfigDirector
  module OpenFeature
    module Internal
      class FlagReader
        def initialize(client)
          @client = client
        end

        def read(flag_key, default_value, evaluation_context)
          ResolutionDetailsByReason.of_the_evaluation(
            @client.evaluate(flag_key, default_value, ConfigDirectorContext.of(evaluation_context))
          )
        end

        def read_a_number(flag_key, default_value, evaluation_context)
          evaluation = @client.evaluate(
            flag_key, float_of(default_value), ConfigDirectorContext.of(evaluation_context)
          )
          ResolutionDetailsByReason.of_the_evaluation(
            evaluation.with(value: number_served_by(evaluation, default_value))
          )
        end

        private

        def float_of(number)
          number.to_f
        end

        def number_served_by(evaluation, default_value)
          return default_value if evaluation.default_value?

          served_number = evaluation.value
          served_number.to_i == served_number ? served_number.to_i : served_number
        end
      end
    end
  end
end
