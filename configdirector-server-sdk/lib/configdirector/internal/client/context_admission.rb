# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class ContextAdmission
        LOG_AN_INVALID_KIND = {
          new_kind_sample: lambda do |log, kind_sample|
            log.error(
              "Ignored a context with the invalid kind '#{kind_sample}' and evaluated as if no context was " \
              "supplied. A context kind has 1 to 64 characters, using only lowercase letters, digits, '-' and '_'."
            )
          end,
          known_kind_sample: ->(_log, _kind_sample) {},
          first_beyond_sample_limit: lambda do |log, _kind_sample|
            log.error(
              "Ignored a context with another invalid kind and evaluated as if no context was supplied. " \
              "#{Telemetry::InvalidContextSubmissions::DISTINCT_KIND_SAMPLE_LIMIT} different invalid kinds were " \
              "logged recently, so further invalid kinds are not logged individually."
            )
          end,
          beyond_sample_limit: ->(_log, _kind_sample) {}
        }.freeze

        private_constant :LOG_AN_INVALID_KIND

        def initialize(log, telemetry)
          @log = log
          @telemetry = telemetry
        end

        def admitted_context_or_none(context)
          return nil if context.nil?

          unless context.is_a?(Context)
            raise ConfigDirectorValidationError,
                  "Invalid context of class #{context.class}. A context must be a ConfigDirector::Context."
          end
          return context if context.kind.nil? || ContextKind.valid?(context.kind)

          kind_sample = ContextKind.sample_of(context.kind)
          LOG_AN_INVALID_KIND.fetch(@telemetry.count_invalid_context(kind_sample)).call(@log, kind_sample)
          nil
        end
      end
    end
  end
end
