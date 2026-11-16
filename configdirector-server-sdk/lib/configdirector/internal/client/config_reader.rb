# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class ConfigReader
        def initialize(serving_state:, event_handlers:, telemetry:, log:)
          @serving_state = serving_state
          @event_handlers = event_handlers
          @telemetry = telemetry
          @log = log
          @context_admission = ContextAdmission.new(log, telemetry)
        end

        def config_read_of(config_key, default_value, context)
          ConfigRead.new(
            config_key: config_key,
            in_code_default_value: Value::InCodeDefaultValue.from(default_value),
            context: @context_admission.admitted_context_or_none(context)
          )
        end

        def evaluation_of(config_key, default_value, context)
          read(config_read_of(config_key, default_value, context))
        end

        def read(config_read)
          evaluated_read = @serving_state.served_configs&.evaluated_read(config_read) ||
                           config_read.evaluated_to_the_in_code_default_value("client-not-ready", nil)
          @telemetry.record_evaluation(evaluated_read)
          evaluation = evaluated_read.evaluation
          @log.debug { "Evaluated #{evaluation.key.inspect} to #{evaluation.value.inspect} (#{evaluation.reason})" }
          @event_handlers.deliver_config_evaluated(evaluation)
          evaluation
        end

        def states(context, config_keys)
          reject_config_keys_that_are_not_an_array(config_keys)
          admitted_context = @context_admission.admitted_context_or_none(context)

          @serving_state.served_configs&.states(admitted_context, config_keys) || {}
        end

        private

        def reject_config_keys_that_are_not_an_array(config_keys)
          return if config_keys.nil? || config_keys.is_a?(Array)

          raise ConfigDirectorValidationError,
                "Invalid config keys of class #{config_keys.class}. The config keys must be an Array of Strings."
        end
      end
    end
  end
end
