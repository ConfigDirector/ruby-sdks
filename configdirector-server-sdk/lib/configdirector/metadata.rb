# frozen_string_literal: true

module ConfigDirector
  # Metadata about your application. Give it to {ConfigDirector.create_client} so that targeting rules can
  # use your application's name and version. Metadata cannot be changed once built, and compares by value.
  class Metadata
    include Internal::ComparedByValue

    # @return [String, nil] the name of your application
    attr_reader :app_name

    # @return [String, nil] the version of your application
    attr_reader :app_version

    # @param app_name [String, nil] the name of your application
    # @param app_version [String, nil] the version of your application
    def initialize(app_name: nil, app_version: nil)
      @app_name = Internal::UnchangeableCopy.of(app_name)
      @app_version = Internal::UnchangeableCopy.of(app_version)
      freeze
    end
  end
end
