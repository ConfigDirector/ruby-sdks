# frozen_string_literal: true

module ConfigDirector
  # What the +config_evaluated+ handlers receive each time a config is evaluated, before the read returns.
  # Two events with the same evaluation are equal.
  class ConfigEvaluatedEvent
    include Internal::ComparedByValue

    # @return [ConfigEvaluation] the evaluation the read returned
    attr_reader :evaluation

    # @param evaluation [ConfigEvaluation] the evaluation the read returned
    def initialize(evaluation:)
      @evaluation = evaluation
      freeze
    end
  end
end
