# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      PollingInterval = Data.define(:configured_seconds)

      class PollingInterval
        MINIMUM_SECONDS = 60

        def raised_to_the_minimum?
          configured_seconds < MINIMUM_SECONDS
        end

        def seconds
          raised_to_the_minimum? ? MINIMUM_SECONDS : configured_seconds
        end
      end
    end
  end
end
