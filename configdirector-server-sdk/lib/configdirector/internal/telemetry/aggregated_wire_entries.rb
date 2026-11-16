# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      module AggregatedWireEntries
        def self.of(counts_by_wire_event, counted_since:, counted_until:)
          start_time = ReportedTime.of(counted_since || counted_until)
          end_time = ReportedTime.of(counted_until)

          counts_by_wire_event.map do |wire_event, count|
            { startTime: start_time, endTime: end_time, count: count, event: wire_event }
          end
        end
      end
    end
  end
end
