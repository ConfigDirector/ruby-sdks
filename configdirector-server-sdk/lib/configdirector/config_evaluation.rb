# frozen_string_literal: true

module ConfigDirector
  ConfigEvaluation = Data.define(:key, :value, :default_value, :reason, :value_id, :variation, :context)

  # One evaluation of a config: the value it returned, why, and the context it was evaluated for. Two
  # evaluations with the same values are equal.
  #
  # @!attribute [r] key
  #   @return [String] the config key that was evaluated
  # @!attribute [r] value
  #   @return [Boolean, String, Integer, Float, Hash, Array] the value returned, which is the in-code
  #     default value when {#default_value?} is +true+
  # @!attribute [r] reason
  #   @return [String] why the evaluation returned this value. +"found-match"+ returns a value from
  #     ConfigDirector. +"rollout-skipped-no-identifier"+ returns the default targeting rule value: a
  #     percentage rollout was skipped because the context has no +id+ to place it in a share, and no rule
  #     after the rollout applied. Every other reason returns the in-code default value: the config has no
  #     value (+"value-missing"+), no config has the key (+"config-state-missing"+), no values have arrived
  #     yet or the client is closed (+"client-not-ready"+), or the value cannot be read as the class of the
  #     in-code default value (+"type-mismatch"+, +"invalid-number"+, +"invalid-json"+,
  #     +"invalid-boolean"+).
  # @!attribute [r] value_id
  #   @return [String, nil] the ID ConfigDirector assigned to the value returned, when it sent one. It is
  #     +nil+ when the in-code default value is returned.
  # @!attribute [r] variation
  #   @return [Variation, nil] the variation served, or +nil+ when the config has no variations or the
  #     in-code default value is returned
  # @!attribute [r] context
  #   @return [Context, nil] the context the config was evaluated for, or +nil+ when none was given or it
  #     was ignored for an invalid kind
  class ConfigEvaluation
    # @param key [String] the config key that was evaluated
    # @param value [Boolean, String, Integer, Float, Hash, Array] the value returned
    # @param default_value [Boolean] whether the value returned is the in-code default value
    # @param reason [String] why the evaluation returned this value
    # @param value_id [String, nil] the ID ConfigDirector assigned to the value returned
    # @param variation [Variation, nil] the variation served
    # @param context [Context, nil] the context the config was evaluated for
    def initialize(key:, value:, default_value:, reason:, value_id: nil, variation: nil, context: nil)
      super
    end

    # @return [Boolean] whether the evaluation returned the in-code default value
    def default_value?
      default_value
    end

    private :default_value
  end
end
