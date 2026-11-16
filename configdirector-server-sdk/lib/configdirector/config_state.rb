# frozen_string_literal: true

module ConfigDirector
  ConfigState = Data.define(:id, :key, :type, :value, :value_id, :variation, :rule_id, :share_id)

  # What a config serves to a context, before its value is read as a Ruby value. Two states with the same
  # values are equal.
  #
  # @!attribute [r] id
  #   @return [String] the config's ID
  # @!attribute [r] key
  #   @return [String] the config key
  # @!attribute [r] type
  #   @return [String] the config's type, such as +"boolean"+, +"string"+, +"integer"+, +"float"+,
  #     +"enum"+, +"url"+ or +"json"+
  # @!attribute [r] value
  #   @return [String, nil] the value served, as text
  # @!attribute [r] value_id
  #   @return [String, nil] the ID ConfigDirector assigned to the value served, when it sent one
  # @!attribute [r] variation
  #   @return [Variation, nil] the variation served, or +nil+ when the config has no variations
  # @!attribute [r] rule_id
  #   @return [String, nil] the ID of the percentage rollout's targeting rule, when a rollout served the value
  # @!attribute [r] share_id
  #   @return [String, nil] the ID of the percentage rollout's share, when a rollout served the value
  class ConfigState
    # @param id [String] the config's ID
    # @param key [String] the config key
    # @param type [String] the config's type
    # @param value [String, nil] the value served, as text
    # @param value_id [String, nil] the ID ConfigDirector assigned to the value served
    # @param variation [Variation, nil] the variation served
    # @param rule_id [String, nil] the ID of the percentage rollout's targeting rule
    # @param share_id [String, nil] the ID of the percentage rollout's share
    def initialize(id:, key:, type:, value:, value_id: nil, variation: nil, rule_id: nil, share_id: nil)
      super
    end
  end
end
