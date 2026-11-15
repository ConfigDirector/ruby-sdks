# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      class OfflineModeConnection
        def self.for_a_client_with(**)
          new
        end

        def open(**)
          yield ServerSdkPayload.without_definitions

          :values_awaited
        end

        def close; end
      end
    end
  end
end
