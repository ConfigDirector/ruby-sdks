# frozen_string_literal: true

module ConfigDirector
  Metadata = Data.define(:app_name, :app_version)

  # Metadata about your application. Give it to {ConfigDirector.create_client} so that targeting rules can
  # use your application's name and version. Metadata cannot be changed once built, compares by value, and
  # +with+ builds a copy with other values.
  #
  # @!attribute [r] app_name
  #   @return [String, nil] the name of your application
  # @!attribute [r] app_version
  #   @return [String, nil] the version of your application
  class Metadata
    # @param app_name [String, nil] the name of your application
    # @param app_version [String, nil] the version of your application
    def initialize(app_name: nil, app_version: nil)
      super(app_name: Internal::UnchangeableCopy.of(app_name), app_version: Internal::UnchangeableCopy.of(app_version))
    end
  end
end
