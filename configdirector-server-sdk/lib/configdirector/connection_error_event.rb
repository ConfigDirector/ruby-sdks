# frozen_string_literal: true

module ConfigDirector
  # What the +connection_error+ handlers receive when ConfigDirector refuses the connection and the client
  # will not try again. Two events with the same error are equal.
  #
  # @!attribute [r] error
  #   @return [ConfigDirectorConnectionError] why the connection failed. Its +status+ is the HTTP status
  #     ConfigDirector answered with.
  ConnectionErrorEvent = Data.define(:error)
end
