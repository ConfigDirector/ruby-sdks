# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      TelemetryReport = Data.define(
        :evaluations, :evaluations_collected_since, :evaluations_dropped, :captured_contexts,
        :captured_contexts_dropped, :invalid_context_wire_entries, :taken_at
      )

      class TelemetryReport
        def empty?
          evaluations.empty? && captured_contexts.empty? && invalid_context_wire_entries.empty? &&
            evaluations_dropped.zero? && captured_contexts_dropped.zero?
        end

        def wire_events
          {
            discreteEvents: { capturedContexts: captured_contexts.map(&:wire_context) },
            aggregatedEvents: { evaluatedConfig: aggregated_evaluations, invalidContext: invalid_context_wire_entries },
            droppedEvents: { evaluatedConfig: evaluations_dropped, capturedContexts: captured_contexts_dropped }
          }
        end

        private

        def aggregated_evaluations
          AggregatedWireEntries.of(
            counts_by_wire_event, counted_since: evaluations_collected_since, counted_until: taken_at
          )
        end

        def counts_by_wire_event
          counts_by_wire_event = Hash.new(0)
          evaluations.tally.each { |evaluation, count| counts_by_wire_event[evaluation.wire_event] += count }

          counts_by_wire_event
        end
      end
    end
  end
end
