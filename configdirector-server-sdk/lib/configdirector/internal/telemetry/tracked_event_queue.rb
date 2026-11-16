# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      class TrackedEventQueue
        EVENTS_PER_REPORT = 1_000

        attr_reader :entries

        def initialize
          discard
        end

        def add(admission)
          warnings_not_logged_for_this_report = keep(admission).reject do |warning|
            @warnings_logged_for_this_report.include?(warning)
          end
          @warnings_logged_for_this_report.merge(warnings_not_logged_for_this_report)

          warnings_not_logged_for_this_report.map do |warning|
            "#{TrackedEventWarning.message_of(warning)} " \
              "Further tracked events like it are not logged until the next telemetry batch is sent."
          end
        end

        def discard
          @entries = []
          @warnings_logged_for_this_report = Set.new
        end

        private

        def keep(admission)
          case admission
          when DroppedTrackedEvent then admission.warnings
          when AdmittedTrackedEvent
            return [:batch_already_full] if @entries.length >= EVENTS_PER_REPORT

            @entries << admission.entry
            admission.warnings
          end
        end
      end
    end
  end
end
