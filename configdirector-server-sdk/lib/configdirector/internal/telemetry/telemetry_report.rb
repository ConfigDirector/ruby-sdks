# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      TelemetryReport = Data.define(
        :evaluations, :evaluations_collected_since, :evaluations_dropped, :captured_contexts,
        :captured_contexts_dropped, :invalid_context_wire_entries, :tracked_events, :taken_at
      )

      class TelemetryReport
        def empty?
          evaluations.empty? && captured_contexts.empty? && invalid_context_wire_entries.empty? &&
            tracked_events.empty? && evaluations_dropped.zero? && captured_contexts_dropped.zero?
        end

        def wire_events
          {
            discreteEvents: {
              capturedContexts: captured_contexts.map(&:wire_context), trackedEvents: tracked_events.map(&:wire_entry)
            },
            aggregatedEvents: { evaluatedConfig: aggregated_evaluations, invalidContext: invalid_context_wire_entries },
            droppedEvents: wire_counts_of_what_was_dropped
          }
        end

        private

        def wire_counts_of_what_was_dropped
          {
            evaluatedConfig: AggregatedWireEntries.count_the_sdk_server_reads(evaluations_dropped),
            capturedContexts: AggregatedWireEntries.count_the_sdk_server_reads(captured_contexts_dropped)
          }
        end

        def aggregated_evaluations
          AggregatedWireEntries.of(
            counts_by_wire_event, counted_since: evaluations_collected_since, counted_until: taken_at
          )
        end

        def counts_by_wire_event
          evaluations.tally.each_with_object(Hash.new(0)) do |(evaluation, count), counts|
            counts[evaluation.wire_event] += count
          end
        end
      end
    end
  end
end
