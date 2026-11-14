# frozen_string_literal: true

require "uri"

module ConfigDirector
  module Internal
    module Client
      module ClientOptionsValidation
        CONNECTION_MODES = %w[streaming polling offline].freeze
        OFFLINE_MODE = "offline"
        EVENT_QUEUE_LIMITS = (100..100_000)
        LOGGER_METHODS = %i[debug info warn error].freeze

        def self.reject_unusable(server_sdk_key:, metadata:, connection:, telemetry:, hooks:, logger:)
          reject_an_option_of_another_class("metadata", metadata, Metadata)
          reject_an_option_of_another_class("connection", connection, ConnectionOptions)
          reject_an_option_of_another_class("telemetry", telemetry, TelemetryOptions)
          reject_an_option_of_another_class("hooks", hooks, ClientHooks)
          reject_an_unusable_logger(logger)
          reject_an_unusable_connection(connection)
          unless connection.mode == OFFLINE_MODE
            reject_an_unusable_server_sdk_key_or_url(server_sdk_key, connection.url)
          end
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

        def self.reject_an_unusable_connection(connection)
          unless CONNECTION_MODES.include?(connection.mode)
            raise ConfigDirectorValidationError,
                  "Unknown connection mode #{connection.mode.inspect}. " \
                  "Expected one of: #{CONNECTION_MODES.map(&:inspect).join(", ")}."
          end

          reject_unusable_durations(connection)
        end

        def self.reject_unusable_durations(connection)
          unless positive_finite_number?(connection.timeout)
            raise ConfigDirectorValidationError,
                  "Invalid timeout '#{connection.timeout}'. The timeout must be a positive number of seconds."
          end
          return if finite_number?(connection.polling_interval)

          raise ConfigDirectorValidationError,
                "Invalid polling interval '#{connection.polling_interval}'. " \
                "The polling interval must be a number of seconds."
        end

        def self.reject_an_unusable_server_sdk_key_or_url(server_sdk_key, url)
          unless server_sdk_key.is_a?(String) && !server_sdk_key.strip.empty?
            raise ConfigDirectorValidationError,
                  "No server SDK key was provided, the client cannot be instantiated without a valid server SDK key"
          end
          return if http_url?(url)

          raise ConfigDirectorValidationError, "Invalid base URL '#{url}'. The base URL must be an http or https URL."
        end

        def self.reject_unusable_telemetry(telemetry)
          event_queue_limit = telemetry.event_queue_limit
          unless event_queue_limit.is_a?(Integer) && EVENT_QUEUE_LIMITS.cover?(event_queue_limit)
            raise ConfigDirectorValidationError,
                  "Invalid telemetry event queue limit '#{event_queue_limit}'. It must be a whole number " \
                  "between #{EVENT_QUEUE_LIMITS.min} and #{EVENT_QUEUE_LIMITS.max}."
          end
          return if positive_finite_number?(telemetry.flush_interval)

          raise ConfigDirectorValidationError,
                "Invalid telemetry flush interval '#{telemetry.flush_interval}'. " \
                "It must be a positive number of seconds."
        end

        def self.finite_number?(value)
          case value
          when Integer then value.abs <= Float::MAX
          when Float then value.finite?
          else false
          end
        end

        def self.positive_finite_number?(value)
          finite_number?(value) && value.positive?
        end

        def self.http_url?(url)
          return false unless url.is_a?(String)

          uri = URI.parse(url)
          uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
        rescue URI::InvalidURIError
          false
        end

        private_constant :CONNECTION_MODES, :OFFLINE_MODE, :EVENT_QUEUE_LIMITS, :LOGGER_METHODS
        private_class_method :reject_an_option_of_another_class, :reject_an_unusable_logger,
                             :reject_an_unusable_connection, :reject_unusable_durations,
                             :reject_an_unusable_server_sdk_key_or_url,
                             :reject_unusable_telemetry, :finite_number?, :positive_finite_number?, :http_url?
      end
    end
  end
end
