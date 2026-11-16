# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      TrackedEventEntry = Data.define(:name, :context_kind, :context_identifier, :value, :details, :happened_at)

      class TrackedEventEntry
        def self.of(name:, context:, value:, details:, happened_at:)
          reported_context = ReportedContext.of(context)

          new(
            name: name, context_kind: reported_context&.kind, context_identifier: reported_context&.identifier,
            value: value, details: details, happened_at: happened_at
          )
        end

        def wire_entry
          {
            name: name, contextKind: context_kind, contextIdentifier: context_identifier, value: value,
            details: details, happenedAt: ReportedTime.of(happened_at)
          }.compact
        end
      end
    end
  end
end
