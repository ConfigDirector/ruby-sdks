# frozen_string_literal: true

module ConfigDirector
  ConfigsUpdatedEvent = Data.define(:keys, :removed_keys)

  # What the +configs_updated+ handlers receive each time the client receives values from ConfigDirector,
  # the first time included. Two events with the same keys are equal.
  #
  # @!attribute [r] keys
  #   @return [Array<String>] the keys of the configs the client received, in the order ConfigDirector sent
  #     them, followed by the configs whose targeting rules use a segment the client received
  # @!attribute [r] removed_keys
  #   @return [Array<String>] the keys of the configs the client no longer serves, because the values it
  #     received left them out or because it could not read their new definition, in the order the client
  #     had them. It is empty when nothing was removed.
  class ConfigsUpdatedEvent
    # @param keys [Array<String>] the keys of the configs the client received
    # @param removed_keys [Array<String>] the keys of the configs the client no longer serves
    def initialize(keys:, removed_keys:)
      super(keys: Internal::UnchangeableCopy.of(keys), removed_keys: Internal::UnchangeableCopy.of(removed_keys))
    end
  end
end
