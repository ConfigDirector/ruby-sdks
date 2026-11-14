# frozen_string_literal: true

module ConfigDirector
  # Handlers for the events a client emits, given to {ConfigDirector.create_client}.
  class ClientHooks
    include Internal::ComparedByValue

    # Creates hooks without handlers.
    def initialize
      freeze
    end
  end
end
