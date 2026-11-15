# frozen_string_literal: true

module ConfigDirector
  # What the +connection_error+ handlers receive when ConfigDirector refuses the connection and the client
  # will not try again. Two events with the same error are equal.
  class ConnectionErrorEvent
    include Internal::ComparedByValue

    # @return [Exception] why the connection failed
    attr_reader :error

    # @param error [Exception] why the connection failed
    def initialize(error:)
      @error = error
      freeze
    end
  end
end
