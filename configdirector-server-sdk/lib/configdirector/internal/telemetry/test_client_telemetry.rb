# frozen_string_literal: true

require "json"

module ConfigDirector
  module Internal
    module Telemetry
      class TestClientTelemetry < DiscardedTelemetry
        attr_reader :tracked_events

        def initialize
          super
          @tracked_events = []
        end

        def record_tracked_event(admission)
          case admission
          when AdmittedTrackedEvent then @tracked_events << tracked_event_recorded_from(admission)
          when DroppedTrackedEvent then nil
          end
          admission.warnings.map { |warning| TrackedEventWarning.message_of(warning) }
        end

        private

        def tracked_event_recorded_from(admission)
          entry = admission.entry

          Testing::TrackedEvent.new(
            name: entry.name, context: admission.context, value: entry.value,
            details: entry.details && JSON.parse(entry.details.text)
          )
        end
      end
    end
  end
end
