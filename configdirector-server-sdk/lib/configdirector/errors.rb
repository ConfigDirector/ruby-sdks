# frozen_string_literal: true

module ConfigDirector
  # The base class of every error the ConfigDirector SDK raises.
  class ConfigDirectorError < StandardError; end

  # Raised when the SDK is given something it cannot use, such as a missing server SDK key or a +nil+
  # in-code default value.
  class ConfigDirectorValidationError < ConfigDirectorError; end

  # Describes a failure to get values from ConfigDirector. A +connection_error+ handler receives it in a
  # {ConnectionErrorEvent}.
  class ConfigDirectorConnectionError < ConfigDirectorError
    # @return [Integer, nil] the HTTP status ConfigDirector answered with, or +nil+ when there was no answer
    attr_reader :status

    # @param message [String, nil] what failed
    # @param status [Integer, nil] the HTTP status ConfigDirector answered with, or +nil+ when there was no
    #   answer
    def initialize(message = nil, status: nil)
      super(message)
      @status = status
    end
  end
end
