# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class EventTracking
        TRACKS_EVENTS_BY_MODE = {
          "streaming" => true,
          "polling" => true,
          "offline" => false,
          "test" => true
        }.freeze

        private_constant :TRACKS_EVENTS_BY_MODE

        def initialize(mode:, telemetry:, log:)
          @tracks_events = TRACKS_EVENTS_BY_MODE.fetch(mode)
          @telemetry = telemetry
          @log = log
          @context_admission = ContextAdmission.new(log, telemetry)
        end

        def track(event_name, context, value, details)
          return unless @tracks_events

          admission = Telemetry::TrackedEventAdmission.of(
            name: event_name, context: @context_admission.admitted_context_or_none(context), value: value,
            details: details, happened_at: Time.now
          )
          @telemetry.record_tracked_event(admission).each { |warning| @log.warn(warning) }
          nil
        rescue StandardError => e
          @log.warn("A tracked event was not reported because it could not be read: #{e.class}: #{e.message.inspect}")
          nil
        end
      end
    end
  end
end
