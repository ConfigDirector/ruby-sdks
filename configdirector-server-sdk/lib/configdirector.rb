# frozen_string_literal: true

require_relative "configdirector/version"
require_relative "configdirector/errors"
require_relative "configdirector/internal"
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
require_relative "configdirector/configs_updated_event"
require_relative "configdirector/config_evaluated_event"
require_relative "configdirector/connection_error_event"
require_relative "configdirector/subscription"
require_relative "configdirector/internal/evaluation"
require_relative "configdirector/internal/value/typed_value"
require_relative "configdirector/internal/value/in_code_default_value"
require_relative "configdirector/internal/value/served_text"
require_relative "configdirector/internal/value/unservable_value"
require_relative "configdirector/internal/value/plain_decimal_text"
require_relative "configdirector/internal/value/utf8_text"
require_relative "configdirector/internal/value/hash_keys"
require_relative "configdirector/internal/value/native_values"
require_relative "configdirector/internal/value/json_position"
require_relative "configdirector/internal/value/json_contents"
require_relative "configdirector/internal/value/encoded_native_value"
require_relative "configdirector/internal/server_sent_events/server_sent_event"
require_relative "configdirector/internal/server_sent_events/event_stream_limit_exceeded"
require_relative "configdirector/internal/server_sent_events/event_stream_parser"
require_relative "configdirector/internal/identity/sdk_identity"
require_relative "configdirector/internal/identity/wrapper"
require_relative "configdirector/internal/connection/not_a_server_sdk_payload"
require_relative "configdirector/internal/connection/unreadable_definition"
require_relative "configdirector/internal/connection/server_sdk_payload"
require_relative "configdirector/internal/connection/config_definition"
require_relative "configdirector/internal/connection/wire_fields"
require_relative "configdirector/internal/connection/condition_parser"
require_relative "configdirector/internal/connection/targeting_rules_parser"
require_relative "configdirector/internal/connection/server_sdk_payload_parser"
require_relative "configdirector/internal/connection/offline_values_file"
require_relative "configdirector/internal/connection/offline_mode_connection"
require_relative "configdirector/internal/connection/polling_interval"
require_relative "configdirector/internal/connection/json_post_request"
require_relative "configdirector/internal/connection/request_deadline"
require_relative "configdirector/internal/connection/http_session"
require_relative "configdirector/internal/connection/retry_after_header"
require_relative "configdirector/internal/logging/default_logger"
require_relative "configdirector/internal/logging/client_log"
require_relative "configdirector/internal/stoppable_thread"
require_relative "configdirector/internal/streaming/stream_timing"
require_relative "configdirector/internal/streaming/stream_endpoint"
require_relative "configdirector/internal/streaming/reconnection_delay"
require_relative "configdirector/internal/streaming/stream_end"
require_relative "configdirector/internal/streaming/stream_connection"
require_relative "configdirector/internal/streaming/heartbeats"
require_relative "configdirector/internal/streaming/reconnecting_stream"
require_relative "configdirector/internal/streaming/streaming_transport"
require_relative "configdirector/internal/streaming/streaming_mode_connection"
require_relative "configdirector/internal/polling/poll_timing"
require_relative "configdirector/internal/polling/refusal_detail"
require_relative "configdirector/internal/polling/poll_answer"
require_relative "configdirector/internal/polling/polling_endpoint"
require_relative "configdirector/internal/polling/poll_request"
require_relative "configdirector/internal/polling/polling_session"
require_relative "configdirector/internal/polling/polling_transport"
require_relative "configdirector/internal/polling/polling_mode_connection"
require_relative "configdirector/internal/telemetry/value_id"
require_relative "configdirector/internal/telemetry/reported_text"
require_relative "configdirector/internal/telemetry/written_json"
require_relative "configdirector/internal/telemetry/compact_json_text"
require_relative "configdirector/internal/telemetry/reported_value"
require_relative "configdirector/internal/telemetry/reported_time"
require_relative "configdirector/internal/telemetry/aggregated_wire_entries"
require_relative "configdirector/internal/telemetry/reported_context"
require_relative "configdirector/internal/telemetry/reported_evaluation"
require_relative "configdirector/internal/telemetry/invalid_context_submissions"
require_relative "configdirector/internal/telemetry/reported_details"
require_relative "configdirector/internal/telemetry/tracked_event_entry"
require_relative "configdirector/internal/telemetry/tracked_event_queue"
require_relative "configdirector/internal/telemetry/tracked_event_admission"
require_relative "configdirector/internal/telemetry/tracked_event_warning"
require_relative "configdirector/internal/telemetry/telemetry_report"
require_relative "configdirector/internal/telemetry/collected_telemetry"
require_relative "configdirector/internal/telemetry/report_timing"
require_relative "configdirector/internal/telemetry/report_answer"
require_relative "configdirector/internal/telemetry/telemetry_endpoint"
require_relative "configdirector/internal/telemetry/event_reporter"
require_relative "configdirector/internal/telemetry/report_schedule"
require_relative "configdirector/internal/telemetry/discarded_telemetry"
require_relative "configdirector/internal/telemetry/reported_telemetry"
require_relative "configdirector/internal/client/number_of_seconds"
require_relative "configdirector/internal/client/connection_options_validation"
require_relative "configdirector/internal/client/client_options_validation"
require_relative "configdirector/internal/client/context_kind"
require_relative "configdirector/internal/client/context_admission"
require_relative "configdirector/internal/client/evaluated_read"
require_relative "configdirector/internal/client/config_read"
require_relative "configdirector/internal/client/served_configs"
require_relative "configdirector/internal/client/serving_state"
require_relative "configdirector/internal/client/registrations"
require_relative "configdirector/internal/client/event_handlers"
require_relative "configdirector/internal/client/watches"
require_relative "configdirector/internal/client/config_reader"
require_relative "configdirector/internal/client/event_tracking"
require_relative "configdirector/internal/client/connection_intake"
require_relative "configdirector/internal/client/what_follows_a_fork"
require_relative "configdirector/internal/client/restart_in_forked_processes"
require_relative "configdirector/internal/client/live_client_connections"
require_relative "configdirector/internal/client/client_connection"
require_relative "configdirector/internal/client/client_factory"
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
  # @raise [ConfigDirectorValidationError] when the server SDK key is missing or blank, +connection.url+
  #   is not an http or https URL, +connection.timeout+ is not a positive number, or +connection.file+ or
  #   +connection.values+ is given, all outside offline mode only; when +connection.mode+ is not a connection
  #   mode; in offline mode, when +connection.timeout+ is not a number, when both +connection.file+ and
  #   +connection.values+ are given, when +connection.values+ is not a Hash or +connection.file+ is neither
  #   a String nor a Pathname, or when +connection.values+ holds a key that is blank, of another class, not
  #   UTF-8 text or given twice, or a value the SDK cannot serve; when +telemetry.flush_interval+ is not a
  #   positive number; when +connection.polling_interval+ is not a number; when +telemetry.event_queue_limit+
  #   is not a whole number from 100 to 100,000; when an option is not an object of its option class; when
  #   the +logger+ lacks one of the four methods; or when +log_level+ is not a level and no +logger+ is given
  def self.create_client(
    server_sdk_key = nil, metadata: nil, connection: nil, logger: nil, log_level: nil, telemetry: nil, hooks: nil
  )
    Internal::Client::ClientFactory.client_identified_as(
      Internal::Identity::SdkIdentity.of_the_server_sdk, server_sdk_key,
      metadata: metadata, connection: connection, logger: logger, log_level: log_level, telemetry: telemetry,
      hooks: hooks
    )
  end
end
