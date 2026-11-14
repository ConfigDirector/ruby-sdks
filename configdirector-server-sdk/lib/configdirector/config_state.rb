# frozen_string_literal: true

module ConfigDirector
  # What a config serves to a context, before its value is read as a Ruby value. Two states with the same
  # values are equal.
  class ConfigState
    include Internal::ComparedByValue

    # @return [String] the config's ID
    attr_reader :id

    # @return [String] the config key
    attr_reader :key

    # @return [String] the config's type, such as +"boolean"+, +"string"+, +"integer"+, +"float"+,
    #   +"enum"+, +"url"+ or +"json"+
    attr_reader :type

    # @return [String, nil] the value served, as text
    attr_reader :value

    # @return [String, nil] the ID ConfigDirector assigned to the value served, when it sent one
    attr_reader :value_id

    # @return [Variation, nil] the variation served, or +nil+ when the config has no variations
    attr_reader :variation

    # @return [String, nil] the ID of the percentage rollout's targeting rule, when a rollout served the value
    attr_reader :rule_id

    # @return [String, nil] the ID of the percentage rollout's share, when a rollout served the value
    attr_reader :share_id

    # @param id [String] the config's ID
    # @param key [String] the config key
    # @param type [String] the config's type
    # @param value [String, nil] the value served, as text
    # @param value_id [String, nil] the ID ConfigDirector assigned to the value served
    # @param variation [Variation, nil] the variation served
    # @param rule_id [String, nil] the ID of the percentage rollout's targeting rule
    # @param share_id [String, nil] the ID of the percentage rollout's share
    def initialize(id:, key:, type:, value:, value_id: nil, variation: nil, rule_id: nil, share_id: nil)
      @id = id
      @key = key
      @type = type
      @value = value
      @value_id = value_id
      @variation = variation
      @rule_id = rule_id
      @share_id = share_id
      freeze
    end
  end
end
