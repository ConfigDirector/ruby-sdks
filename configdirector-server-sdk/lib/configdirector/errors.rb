# frozen_string_literal: true

module ConfigDirector
  # The base class of every error the ConfigDirector SDK raises.
  class ConfigDirectorError < StandardError; end

  # Raised when the SDK is given something it cannot use, such as a missing server SDK key or a +nil+
  # in-code default value.
  class ConfigDirectorValidationError < ConfigDirectorError; end
end
