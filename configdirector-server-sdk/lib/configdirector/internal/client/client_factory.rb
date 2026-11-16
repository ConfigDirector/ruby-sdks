# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      module ClientFactory
        CONNECTION_CLASS_BY_MODE = {
          "streaming" => Streaming::StreamingModeConnection,
          "polling" => Polling::PollingModeConnection,
          "offline" => Connection::OfflineModeConnection
        }.freeze

        TELEMETRY_CLASS_BY_MODE = {
          "streaming" => Telemetry::ReportedTelemetry,
          "polling" => Telemetry::ReportedTelemetry,
          "offline" => Telemetry::DiscardedTelemetry
        }.freeze

        private_constant :CONNECTION_CLASS_BY_MODE, :TELEMETRY_CLASS_BY_MODE

        def self.client_identified_as(
          sdk_identity, server_sdk_key, metadata:, connection:, logger:, log_level:, telemetry:, hooks:
        )
          metadata, connection, telemetry, hooks = options_or_their_defaults(metadata, connection, telemetry, hooks)
          ClientOptionsValidation.reject_unusable(
            server_sdk_key: server_sdk_key, metadata: metadata, connection: connection, telemetry: telemetry,
            hooks: hooks, logger: logger
          )
          logger ||= Logging::DefaultLogger.writing_from(log_level)

          client_with_usable_options(
            sdk_identity: sdk_identity, server_sdk_key: server_sdk_key.to_s, metadata: metadata,
            connection_options: connection, telemetry_options: telemetry, logger: logger, hooks: hooks
          )
        end

        def self.test_client_serving(values, timeout:, logger:)
          timeout = ConnectionOptions.new.timeout if timeout.nil?
          ConnectionOptionsValidation.reject_a_timeout_that_is_not_positive(timeout)
          ClientOptionsValidation.reject_an_unusable_logger(logger)
          logger ||= Logging::DefaultLogger.writing_from(nil)
          connection = Connection::InMemoryConnection.new(values, timeout_seconds: timeout, logger: logger)
          telemetry = Telemetry::TestClientTelemetry.new

          Testing::TestClient.new(
            client_over_an_in_memory_connection(connection, telemetry, timeout, logger), connection,
            telemetry.tracked_events
          )
        end

        def self.client_with_usable_options(
          sdk_identity:, server_sdk_key:, metadata:, connection_options:, telemetry_options:, logger:, hooks:
        )
          warn_of_a_polling_interval_below_the_minimum(connection_options, logger)
          connection = CONNECTION_CLASS_BY_MODE.fetch(connection_options.mode).for_a_client_with(
            server_sdk_key: server_sdk_key, metadata: metadata, connection_options: connection_options,
            sdk_identity: sdk_identity, logger: logger
          )
          telemetry = TELEMETRY_CLASS_BY_MODE.fetch(connection_options.mode).for_a_client_with(
            server_sdk_key: server_sdk_key, metadata: metadata, connection_options: connection_options,
            telemetry_options: telemetry_options, sdk_identity: sdk_identity, logger: logger
          )

          client_over(connection, telemetry, connection_options, metadata: metadata, logger: logger, hooks: hooks)
        end

        def self.options_or_their_defaults(metadata, connection, telemetry, hooks)
          [
            metadata || Metadata.new, connection || ConnectionOptions.new, telemetry || TelemetryOptions.new,
            hooks || ClientHooks.new
          ]
        end

        def self.client_over(connection, telemetry, connection_options, metadata:, logger:, hooks:)
          ConfigDirectorClient.new(
            connection: connection, telemetry: telemetry, mode: connection_options.mode,
            timeout: connection_options.timeout, metadata: metadata, logger: logger, hooks: hooks
          )
        end

        def self.client_over_an_in_memory_connection(connection, telemetry, timeout, logger)
          ConfigDirectorClient.new(
            connection: connection, telemetry: telemetry, mode: "test", timeout: timeout, metadata: Metadata.new,
            logger: logger, hooks: ClientHooks.new
          )
        end

        def self.warn_of_a_polling_interval_below_the_minimum(connection, logger)
          polling_interval = Connection::PollingInterval.new(configured_seconds: connection.polling_interval)
          return unless connection.mode == "polling" && polling_interval.raised_to_the_minimum?

          Logging::ClientLog.new(logger).warn(
            "polling_interval of #{polling_interval.configured_seconds} seconds is below the " \
            "minimum of #{Connection::PollingInterval::MINIMUM_SECONDS} seconds. " \
            "Using #{polling_interval.seconds} seconds."
          )
        end

        private_class_method :client_with_usable_options, :options_or_their_defaults, :client_over,
                             :client_over_an_in_memory_connection, :warn_of_a_polling_interval_below_the_minimum
      end
    end
  end
end
