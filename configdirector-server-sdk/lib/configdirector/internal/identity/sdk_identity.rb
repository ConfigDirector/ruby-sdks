# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Identity
      class SdkIdentity
        def self.of_the_server_sdk
          new("ruby-server-sdk", VERSION)
        end

        def self.of_the_wrapper(wrapper)
          unless wrapper.is_a?(Wrapper)
            raise ArgumentError, "An SDK identity is made for the SDK itself or for a wrapper the SDK lists."
          end

          new(wrapper.sdk_name, wrapper.version_of_its_gem)
        end

        private_class_method :new

        def initialize(sdk_name, sdk_version)
          @sdk_name = sdk_name
          @sdk_version = sdk_version
          freeze
        end

        def user_agent
          "#{@sdk_name}/#{@sdk_version}"
        end

        def meta_context_of_an_application_with(metadata)
          {
            sdkName: @sdk_name, sdkVersion: @sdk_version, appName: metadata.app_name, appVersion: metadata.app_version
          }.compact
        end
      end
    end
  end
end
