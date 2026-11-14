# frozen_string_literal: true

require_relative "configdirector/version"
require_relative "configdirector/errors"
require_relative "configdirector/internal/compared_by_value"
require_relative "configdirector/internal/unchangeable_copy"
require_relative "configdirector/metadata"
require_relative "configdirector/connection_options"
require_relative "configdirector/telemetry_options"
require_relative "configdirector/client_hooks"
require_relative "configdirector/internal/client/context_attributes"
require_relative "configdirector/context"
require_relative "configdirector/variation"
require_relative "configdirector/config_state"
require_relative "configdirector/config_evaluation"
require_relative "configdirector/internal/evaluation"
require_relative "configdirector/internal/value/typed_value"
require_relative "configdirector/internal/value/in_code_default_value"
require_relative "configdirector/internal/value/served_text"
require_relative "configdirector/internal/connection/server_sdk_payload"
require_relative "configdirector/internal/connection/config_definition"
require_relative "configdirector/internal/connection/hard_coded_connection"
require_relative "configdirector/internal/connection/polling_interval"
require_relative "configdirector/internal/logging/default_logger"
require_relative "configdirector/internal/client/client_options_validation"
require_relative "configdirector/internal/client/context_kind"
require_relative "configdirector/internal/client/invalid_context_kinds"
require_relative "configdirector/internal/client/context_admission"
require_relative "configdirector/internal/client/config_read"
require_relative "configdirector/internal/client/served_configs"
require_relative "configdirector/internal/client/serving_state"
require_relative "configdirector/config_director_client"

# The ConfigDirector server SDK.
module ConfigDirector
  # Creates a ConfigDirector client. It returns a client that is not initialized and makes no network call:
  # call {ConfigDirectorClient#init} before the first read.
  #
  # @example
  #   client = ConfigDirector.create_client(
  #     ENV.fetch("CONFIGDIRECTOR_SERVER_KEY"),
  #     metadata: ConfigDirector::Metadata.new(app_name: "my-awesome-app", app_version: "1.0.0")
  #   )
  #   client.init
  #
  # @param server_sdk_key [String, nil] the ConfigDirector server SDK key. This is a secret value, do not
  #   commit it in your source code. It can be left out in offline mode only.
  # @param metadata [Metadata, nil] metadata about your application. Including +app_name+ and +app_version+
  #   is recommended, so that you can use them in targeting rules.
  # @param connection [ConnectionOptions, nil] how the client connects to ConfigDirector
  # @param logger [#debug, #info, #warn, #error, nil] a logger with the methods of Ruby's +Logger+, such as
  #   +Rails.logger+. The SDK calls each method with one String. Without a logger the SDK writes warnings
  #   and errors to standard error.
  # @param log_level [Integer, Symbol, String, nil] the lowest level the SDK writes when no +logger+ is
  #   given, as Ruby's +Logger+ takes it, such as +:debug+ or +Logger::INFO+. Defaults to +:warn+. It has no
  #   effect when a +logger+ is given.
  # @param telemetry [TelemetryOptions, nil] telemetry tuning
  # @param hooks [ClientHooks, nil] handlers for the events the client emits
  # @return [ConfigDirectorClient] a client that is not initialized
  # @raise [ConfigDirectorValidationError] when the server SDK key is missing or blank or +connection.url+
  #   is not an http or https URL, both outside offline mode only; when +connection.mode+ is not a
  #   connection mode; when +connection.timeout+ or +telemetry.flush_interval+ is not a positive number;
  #   when +connection.polling_interval+ is not a number; when +telemetry.event_queue_limit+ is not a whole
  #   number from 100 to 100,000; when an option is not an object of its option class; when the +logger+
  #   lacks one of the four methods; or when +log_level+ is not a level and no +logger+ is given
  def self.create_client(
    server_sdk_key = nil, metadata: nil, connection: nil, logger: nil, log_level: nil, telemetry: nil, hooks: nil
  )
    metadata ||= Metadata.new
    connection ||= ConnectionOptions.new
    Internal::Client::ClientOptionsValidation.reject_unusable(
      server_sdk_key: server_sdk_key, metadata: metadata, connection: connection,
      telemetry: telemetry || TelemetryOptions.new, hooks: hooks || ClientHooks.new, logger: logger
    )
    logger ||= Internal::Logging::DefaultLogger.writing_from(log_level)
    warn_of_a_polling_interval_below_the_minimum(connection, logger)

    client_on(Internal::Connection::HardCodedConnection.new, metadata, connection, logger)
  end

  def self.client_on(internal_connection, metadata, connection_options, logger)
    ConfigDirectorClient.new(
      connection: internal_connection, metadata: metadata, timeout: connection_options.timeout.to_f, logger: logger
    )
  end

  def self.warn_of_a_polling_interval_below_the_minimum(connection, logger)
    polling_interval = Internal::Connection::PollingInterval.new(configured_seconds: connection.polling_interval)
    return unless connection.mode == "polling" && polling_interval.raised_to_the_minimum?

    logger.warn(
      "[ConfigDirectorClient] polling_interval of #{polling_interval.configured_seconds} seconds is below the " \
      "minimum of #{Internal::Connection::PollingInterval::MINIMUM_SECONDS} seconds. " \
      "Using #{polling_interval.seconds} seconds."
    )
  end

  private_class_method :client_on, :warn_of_a_polling_interval_below_the_minimum
end
