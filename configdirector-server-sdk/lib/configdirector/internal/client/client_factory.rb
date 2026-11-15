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

        private_constant :CONNECTION_CLASS_BY_MODE

        def self.client_identified_as(
          sdk_identity, server_sdk_key, metadata:, connection:, logger:, log_level:, telemetry:, hooks:
        )
          metadata ||= Metadata.new
          connection ||= ConnectionOptions.new
          hooks ||= ClientHooks.new
          ClientOptionsValidation.reject_unusable(
            server_sdk_key: server_sdk_key, metadata: metadata, connection: connection,
            telemetry: telemetry || TelemetryOptions.new, hooks: hooks, logger: logger
          )
          logger ||= Logging::DefaultLogger.writing_from(log_level)

          client_with_usable_options(sdk_identity: sdk_identity, server_sdk_key: server_sdk_key.to_s,
                                     metadata: metadata, connection_options: connection, logger: logger, hooks: hooks)
        end

        def self.client_with_usable_options(
          sdk_identity:, server_sdk_key:, metadata:, connection_options:, logger:, hooks:
        )
          warn_of_a_polling_interval_below_the_minimum(connection_options, logger)

          ConfigDirectorClient.new(
            connection: CONNECTION_CLASS_BY_MODE.fetch(connection_options.mode).for_a_client_with(
              server_sdk_key: server_sdk_key, metadata: metadata, connection_options: connection_options,
              sdk_identity: sdk_identity, logger: logger
            ),
            connection_options: connection_options, metadata: metadata, logger: logger, hooks: hooks
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

        private_class_method :client_with_usable_options, :warn_of_a_polling_interval_below_the_minimum
      end
    end
  end
end
