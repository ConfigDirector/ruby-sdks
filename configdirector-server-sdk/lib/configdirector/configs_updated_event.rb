# frozen_string_literal: true

module ConfigDirector
  # What the +configs_updated+ handlers receive each time the client receives values from ConfigDirector,
  # the first time included. Two events with the same keys are equal.
  class ConfigsUpdatedEvent
    include Internal::ComparedByValue

    # @return [Array<String>] the keys of the configs the client received, in the order ConfigDirector sent
    #   them, followed by the configs whose targeting rules use a segment the client received
    attr_reader :keys

    # @return [Array<String>] the keys of the configs the client no longer serves, because the values it
    #   received left them out or because it could not read their new definition, in the order the client
    #   had them. It is empty when nothing was removed.
    attr_reader :removed_keys

    # @param keys [Array<String>] the keys of the configs the client received
    # @param removed_keys [Array<String>] the keys of the configs the client no longer serves
    def initialize(keys:, removed_keys:)
      @keys = Internal::UnchangeableCopy.of(keys)
      @removed_keys = Internal::UnchangeableCopy.of(removed_keys)
      freeze
    end
  end
end
