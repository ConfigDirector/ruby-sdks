# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      ReportedContext = Data.define(:kind, :identifier, :context)

      class ReportedContext
        KIND_OF_A_CONTEXT_WITHOUT_ONE = "user"

        private_constant :KIND_OF_A_CONTEXT_WITHOUT_ONE

        def self.of(context)
          return nil if context.nil? || context.anonymous?

          identifier = context.id
          return nil if identifier.nil? || identifier.empty?

          new(kind: context.kind || KIND_OF_A_CONTEXT_WITHOUT_ONE, identifier: identifier, context: context)
        end

        def wire_context
          { id: identifier, kind: kind, name: context.name, traits: context.traits }.compact
        end
      end
    end
  end
end
