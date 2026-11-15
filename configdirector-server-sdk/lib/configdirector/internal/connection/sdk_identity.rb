# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      module SdkIdentity
        NAME = "ruby-server-sdk"

        private_constant :NAME

        def self.user_agent
          "#{NAME}/#{VERSION}"
        end

        def self.meta_context_of_an_application_with(metadata)
          { sdkName: NAME, sdkVersion: VERSION, appName: metadata.app_name, appVersion: metadata.app_version }.compact
        end
      end
    end
  end
end
