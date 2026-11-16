# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      module ReportedTime
        def self.of(time)
          time.getutc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
        end
      end
    end
  end
end
