# frozen_string_literal: true

module ConfigDirector
  # One of the values a config can serve, such as the control or a treatment of an experiment. Two variations
  # with the same values are equal.
  class Variation
    include Internal::ComparedByValue

    # @return [String] the ID ConfigDirector assigned to the variation, which stays the same when the
    #   variation is renamed
    attr_reader :id

    # @return [String, nil] the variation's name, when it has one
    attr_reader :name

    # @param id [String] the ID ConfigDirector assigned to the variation
    # @param name [String, nil] the variation's name
    def initialize(id:, name: nil)
      @id = id
      @name = name
      freeze
    end
  end
end
