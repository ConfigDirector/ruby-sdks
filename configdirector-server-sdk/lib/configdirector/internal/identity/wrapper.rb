# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Identity
      class Wrapper
        VERSION_WITHOUT_THE_GEM_OF_THE_WRAPPER = "0.0.0-dev"

        private_constant :VERSION_WITHOUT_THE_GEM_OF_THE_WRAPPER

        attr_reader :sdk_name

        def initialize(sdk_name, name_of_the_version_constant_of_its_gem)
          @sdk_name = sdk_name
          @name_of_the_version_constant_of_its_gem = name_of_the_version_constant_of_its_gem
          freeze
        end

        OPENFEATURE_SERVER_PROVIDER = new("ruby-openfeature-server-provider", "ConfigDirector::OpenFeature::VERSION")

        private_class_method :new

        def create_client(
          server_sdk_key = nil, metadata: nil, connection: nil, logger: nil, log_level: nil, telemetry: nil, hooks: nil
        )
          Client::ClientFactory.client_identified_as(
            SdkIdentity.of_the_wrapper(self), server_sdk_key,
            metadata: metadata, connection: connection, logger: logger, log_level: log_level, telemetry: telemetry,
            hooks: hooks
          )
        end

        def version_of_its_gem
          return VERSION_WITHOUT_THE_GEM_OF_THE_WRAPPER unless gem_loaded?

          version = Object.const_get(@name_of_the_version_constant_of_its_gem)
          version.is_a?(String) ? version : VERSION_WITHOUT_THE_GEM_OF_THE_WRAPPER
        end

        private

        def gem_loaded?
          Object.const_defined?(@name_of_the_version_constant_of_its_gem)
        end
      end
    end
  end
end
