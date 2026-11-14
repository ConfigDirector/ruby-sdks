# frozen_string_literal: true

module ConfigDirector
  # What the +connection_error+ handlers will receive when the connection to ConfigDirector fails and will
  # not be retried. The client does not connect to ConfigDirector yet, so nothing creates one. Two events
  # with the same error are equal.
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
