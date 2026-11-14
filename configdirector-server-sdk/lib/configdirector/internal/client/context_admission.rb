# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class ContextAdmission
        LOG_AN_INVALID_KIND = {
          new_kind_sample: lambda do |logger, kind_sample|
            logger.error(
              "[ConfigDirectorClient] Ignored a context with the invalid kind '#{kind_sample}' and evaluated as " \
              "if no context was supplied. A context kind has 1 to 64 characters, using only lowercase letters, " \
              "digits, '-' and '_'."
            )
          end,
          known_kind_sample: ->(_logger, _kind_sample) {},
          first_beyond_sample_limit: lambda do |logger, _kind_sample|
            logger.error(
              "[ConfigDirectorClient] Ignored a context with another invalid kind and evaluated as if no context " \
              "was supplied. #{InvalidContextKinds::DISTINCT_KIND_SAMPLE_LIMIT} different invalid kinds were " \
              "logged, so further invalid kinds are not logged individually."
            )
          end,
          beyond_sample_limit: ->(_logger, _kind_sample) {}
        }.freeze

        private_constant :LOG_AN_INVALID_KIND

        def initialize(logger)
          @logger = logger
          @invalid_context_kinds = InvalidContextKinds.new
        end

        def admitted_context_or_none(context)
          return nil if context.nil?

          unless context.is_a?(Context)
            raise ConfigDirectorValidationError,
                  "Invalid context of class #{context.class}. A context must be a ConfigDirector::Context."
          end
          return context if context.kind.nil? || ContextKind.valid?(context.kind)

          kind_sample = ContextKind.sample_of(context.kind)
          LOG_AN_INVALID_KIND.fetch(@invalid_context_kinds.record(kind_sample)).call(@logger, kind_sample)
          nil
        end
      end
    end
  end
end
