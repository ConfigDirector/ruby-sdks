# frozen_string_literal: true

module ConfigDirector
  # What the +config_evaluated+ handlers receive each time a config is evaluated, before the read returns.
  # Two events with the same evaluation are equal.
  #
  # @!attribute [r] evaluation
  #   @return [ConfigEvaluation] the evaluation the read returned
  ConfigEvaluatedEvent = Data.define(:evaluation)
end
