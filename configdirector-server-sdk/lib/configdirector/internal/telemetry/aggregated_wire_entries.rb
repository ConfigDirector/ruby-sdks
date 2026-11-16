# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      module AggregatedWireEntries
        LARGEST_COUNT_THE_SDK_SERVER_READS = 2_147_483_647

        private_constant :LARGEST_COUNT_THE_SDK_SERVER_READS

        def self.count_the_sdk_server_reads(count)
          [count, LARGEST_COUNT_THE_SDK_SERVER_READS].min
        end

        def self.of(counts_by_wire_event, counted_since:, counted_until:)
          start_time = ReportedTime.of(counted_since || counted_until)
          end_time = ReportedTime.of(counted_until)

          counts_by_wire_event.map do |wire_event, count|
            { startTime: start_time, endTime: end_time, count: count_the_sdk_server_reads(count), event: wire_event }
          end
        end
      end
    end
  end
end
