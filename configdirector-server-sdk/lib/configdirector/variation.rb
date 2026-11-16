# frozen_string_literal: true

module ConfigDirector
  Variation = Data.define(:id, :name)

  # One of the values a config can serve, such as the control or a treatment of an experiment. Two variations
  # with the same values are equal.
  #
  # @!attribute [r] id
  #   @return [String] the ID ConfigDirector assigned to the variation, which stays the same when the
  #     variation is renamed
  # @!attribute [r] name
  #   @return [String, nil] the variation's name, when it has one
  class Variation
    # @param id [String] the ID ConfigDirector assigned to the variation
    # @param name [String, nil] the variation's name
    def initialize(id:, name: nil)
      super
    end
  end
end
