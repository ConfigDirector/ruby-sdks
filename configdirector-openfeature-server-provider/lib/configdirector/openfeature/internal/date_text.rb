# frozen_string_literal: true

require "date"

module ConfigDirector
  module OpenFeature
    module Internal
      module DateText
        def self.of(value)
          return ConfigDirector::Internal::Telemetry::ReportedTime.of(value) if value.is_a?(Time)

          case value
          when DateTime then ConfigDirector::Internal::Telemetry::ReportedTime.of(value.to_time)
          when Date then value.iso8601
          end
        end
      end
    end
  end
end
