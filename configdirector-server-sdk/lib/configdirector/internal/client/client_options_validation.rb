# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      module ClientOptionsValidation
        EVENT_QUEUE_LIMITS = (100..100_000)
        LOGGER_METHODS = %i[debug info warn error].freeze

        def self.reject_unusable(server_sdk_key:, metadata:, connection:, telemetry:, hooks:, logger:)
          reject_an_option_of_another_class("metadata", metadata, Metadata)
          reject_an_option_of_another_class("connection", connection, ConnectionOptions)
          reject_an_option_of_another_class("telemetry", telemetry, TelemetryOptions)
          reject_an_option_of_another_class("hooks", hooks, ClientHooks)
          reject_an_unusable_logger(logger)
          ConnectionOptionsValidation.reject_unusable(connection, server_sdk_key)
          reject_unusable_telemetry(telemetry)
        end

        def self.reject_an_option_of_another_class(option_name, option, option_class)
          return if option.is_a?(option_class)

          raise ConfigDirectorValidationError,
                "Invalid '#{option_name}' option of class #{option.class}. It must be a #{option_class}."
        end

        def self.reject_an_unusable_logger(logger)
          return if logger.nil? || LOGGER_METHODS.all? { |method_name| logger.respond_to?(method_name) }

          raise ConfigDirectorValidationError,
                "Invalid logger of class #{logger.class}. A logger must respond to debug, info, warn and error."
        end

        def self.reject_unusable_telemetry(telemetry)
          event_queue_limit = telemetry.event_queue_limit
          unless event_queue_limit.is_a?(Integer) && EVENT_QUEUE_LIMITS.cover?(event_queue_limit)
            raise ConfigDirectorValidationError,
                  "Invalid telemetry event queue limit '#{event_queue_limit}'. It must be a whole number " \
                  "between #{EVENT_QUEUE_LIMITS.min} and #{EVENT_QUEUE_LIMITS.max}."
          end
          return if NumberOfSeconds.finite_and_positive?(telemetry.flush_interval)

          raise ConfigDirectorValidationError,
                "Invalid telemetry flush interval '#{telemetry.flush_interval}'. " \
                "It must be a positive number of seconds."
        end

        private_constant :EVENT_QUEUE_LIMITS, :LOGGER_METHODS
        private_class_method :reject_an_option_of_another_class, :reject_an_unusable_logger, :reject_unusable_telemetry
      end
    end
  end
end
