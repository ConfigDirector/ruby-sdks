# frozen_string_literal: true

module ConfigDirector
  module OpenFeature
    # An OpenFeature provider backed by the ConfigDirector Ruby server SDK. Register it with OpenFeature and read
    # values through an OpenFeature client. The provider owns a ConfigDirector client: it connects when OpenFeature
    # initializes the provider and closes when OpenFeature shuts it down. Targeting rules are evaluated in your
    # process, so a read makes no network call.
    #
    # @example
    #   require "configdirector/openfeature"
    #
    #   OpenFeature::SDK.set_provider_and_wait(
    #     ConfigDirector::OpenFeature::ConfigDirectorProvider.new(ENV.fetch("CONFIGDIRECTOR_SERVER_KEY"))
    #   )
    #
    #   client = OpenFeature::SDK.build_client
    #   client.fetch_boolean_value(flag_key: "new-checkout", default_value: false)
    #
    # The OpenFeature evaluation context becomes a ConfigDirector context. The targeting key, or else an +id+
    # attribute, becomes its id, and the +kind+, +name+, +traits+ and +anonymous+ attributes its kind, name, traits
    # and anonymous flag. An id or a name given as a Symbol, +true+ or +false+, an Integer, a Float or a date is read
    # as text, and any other id or name is left out. A date, given as a Time, a DateTime or a Date, is read as UTC
    # text such as +"2026-11-17T10:00:00.000Z"+, or as +"2026-11-17"+ for a Date, inside the traits too, so date
    # conditions can compare it. Traits other than a Hash with at least one entry are left out, a +kind+ inside the
    # traits is an ordinary trait, and the context is anonymous only when +anonymous+ is +true+. Without a +kind+
    # attribute the context is a user. When the kind is invalid, including a kind that is not text, the whole
    # context is ignored: the read still resolves, to the value for no context, and the SDK logs an error. A
    # context with neither a targeting key nor an +id+ attribute skips percentage rollouts: the flag resolves to
    # the default targeting rule value, with the reason +DEFAULT+.
    #
    # The details of a read carry the name of the variation served as their +variant+, or the ID of the value
    # served when it has no named variation.
    #
    # If no config arrives within the connection timeout, or ConfigDirector refuses the server SDK key,
    # initialization fails: +set_provider_and_wait+ raises +OpenFeature::SDK::ProviderInitializationError+ with
    # the error code +PROVIDER_NOT_READY+, the provider reports the +ERROR+ status, and reads return their in-code
    # default value with +PROVIDER_NOT_READY+. The provider keeps connecting, and reports +READY+ once config
    # arrives. To start without waiting for ConfigDirector, register the provider with +set_provider+, which
    # initializes it in the background, or rescue the error.
    #
    # In offline mode, with <tt>connection: ConfigDirector::ConnectionOptions.new(mode: "offline", ...)</tt>, the
    # provider never connects to ConfigDirector and needs no server SDK key. It serves the values of a JSON file or
    # of a Hash to every read, as {ConfigDirector::ConnectionOptions} describes.
    class ConfigDirectorProvider
      include ::OpenFeature::SDK::Provider::EventEmitter

      ProviderEvent = ::OpenFeature::SDK::ProviderEvent
      ErrorCode = ::OpenFeature::SDK::Provider::ErrorCode
      NO_CONFIG_IN_TIME = "No config arrived from ConfigDirector within the connection timeout. " \
                          "Flags resolve to their in-code default values until config arrives."

      private_constant :ProviderEvent, :ErrorCode, :NO_CONFIG_IN_TIME

      # @return [OpenFeature::SDK::Provider::ProviderMetadata] the name the provider is registered under with
      #   OpenFeature, +ConfigDirectorProvider+
      attr_reader :metadata

      # Creates a provider and its ConfigDirector client, which makes no network call until OpenFeature
      # initializes the provider.
      #
      # @param server_sdk_key [String, nil] the ConfigDirector server SDK key. This is a secret value, do not
      #   commit it in your source code. It can be left out in offline mode only.
      # @param metadata [ConfigDirector::Metadata, nil] metadata about your application. Including +app_name+ and
      #   +app_version+ is recommended, so that you can use them in targeting rules.
      # @param connection [ConfigDirector::ConnectionOptions, nil] how the client connects to ConfigDirector
      # @param logger [#debug, #info, #warn, #error, nil] a logger with the methods of Ruby's +Logger+, such as
      #   +Rails.logger+. Without a logger the provider writes warnings and errors to standard error.
      # @param log_level [Integer, Symbol, String, nil] the lowest level written when no +logger+ is given, as
      #   Ruby's +Logger+ takes it, such as +:debug+ or +Logger::INFO+. Defaults to +:warn+. It has no effect when
      #   a +logger+ is given.
      # @param telemetry [ConfigDirector::TelemetryOptions, nil] telemetry tuning
      # @raise [ConfigDirector::ConfigDirectorValidationError] for the options that
      #   {ConfigDirector.create_client} rejects, such as a missing server SDK key outside offline mode
      def initialize(
        server_sdk_key = nil, metadata: nil, connection: nil, logger: nil, log_level: nil, telemetry: nil
      )
        @metadata = ::OpenFeature::SDK::Provider::ProviderMetadata.new(name: "ConfigDirectorProvider").freeze
        @logger = logger || ConfigDirector::Internal::Logging::DefaultLogger.writing_from(log_level)
        @client = ConfigDirector::Internal::Identity::Wrapper::OPENFEATURE_SERVER_PROVIDER.create_client(
          server_sdk_key, metadata: metadata, connection: connection, logger: @logger, telemetry: telemetry
        )
        @startup = Internal::Startup.new(@client)
        @flag_reader = Internal::FlagReader.new(@client)
        @client.on(:configs_updated) { |update| report_the_configs_changed_by(update) }
        @client.on(:client_ready) { send_the_report(@startup.report_due_when_config_arrives) }
      end

      # Tells OpenFeature that the provider reports its own +PROVIDER_READY+ and +PROVIDER_ERROR+ events.
      #
      # @return [true]
      def emits_lifecycle_events?
        true
      end

      # Connects to ConfigDirector and waits up to the connection timeout for config, or loads the offline values
      # in offline mode. OpenFeature calls it when the provider is registered.
      #
      # @return [void]
      # @raise [OpenFeature::SDK::EvaluationError] with the error code +PROVIDER_NOT_READY+, when no config arrives
      #   within the connection timeout or ConfigDirector refuses the server SDK key
      # @raise [ConfigDirector::ConfigDirectorInitializationError] in offline mode, when the offline values cannot
      #   be loaded
      def init
        @startup.begin_initialization
        initialize_the_client
        send_the_report(@startup.report_due_after_initialization)
      end

      # Closes the connection to ConfigDirector and sends the telemetry the client holds. OpenFeature calls it
      # when it shuts down or replaces the provider.
      #
      # @return [void]
      def shutdown
        @client.close
      end

      # Reports to ConfigDirector that something happened, such as a completed checkout, with the next telemetry
      # batch: the details' +value+ as the event's value, their other fields as the event's details, and the
      # evaluation context as the context the event happened for. An event counts for an experiment only when its
      # evaluation context has the targeting key the experiment's flag was evaluated with. It never raises: an
      # event it cannot pass on, for example because the evaluation context cannot be read, is logged as a
      # warning and not reported. It does nothing in offline mode.
      #
      # @param tracking_event_name [String] the event's name, 1 to 150 characters
      # @param evaluation_context [OpenFeature::SDK::EvaluationContext, nil] the context the event happened for
      # @param tracking_event_details [OpenFeature::SDK::TrackingEventDetails, nil] the event's value and details
      # @return [void]
      def track(tracking_event_name, evaluation_context: nil, tracking_event_details: nil)
        @client.track(
          tracking_event_name, Internal::ConfigDirectorContext.of(evaluation_context),
          value: value_of(tracking_event_details), details: details_of(tracking_event_details)
        )
      rescue StandardError => e
        @logger.warn("A tracked event was not reported because it could not be read: #{e.message}")
      end

      # Evaluates a flag as a boolean.
      #
      # @return [OpenFeature::SDK::Provider::ResolutionDetails]
      def fetch_boolean_value(flag_key:, default_value:, evaluation_context: nil)
        @flag_reader.read(flag_key, default_value, evaluation_context)
      end

      # Evaluates a flag as a String.
      #
      # @return [OpenFeature::SDK::Provider::ResolutionDetails]
      def fetch_string_value(flag_key:, default_value:, evaluation_context: nil)
        @flag_reader.read(flag_key, default_value, evaluation_context)
      end

      # Evaluates a flag as any finite number, whatever the class of the in-code default value: a whole number is
      # returned as an Integer and any other number as a Float. When the flag cannot be read as a number, the
      # in-code default value is returned as given.
      #
      # @return [OpenFeature::SDK::Provider::ResolutionDetails]
      def fetch_number_value(flag_key:, default_value:, evaluation_context: nil)
        @flag_reader.read_a_number(flag_key, default_value, evaluation_context)
      end

      # Evaluates a flag as a whole number, returned as an Integer.
      #
      # @return [OpenFeature::SDK::Provider::ResolutionDetails]
      def fetch_integer_value(flag_key:, default_value:, evaluation_context: nil)
        @flag_reader.read(flag_key, default_value, evaluation_context)
      end

      # Evaluates a flag as any finite number, returned as a Float.
      #
      # @return [OpenFeature::SDK::Provider::ResolutionDetails]
      def fetch_float_value(flag_key:, default_value:, evaluation_context: nil)
        @flag_reader.read(flag_key, default_value, evaluation_context)
      end

      # Evaluates a flag as a JSON object, returned as a Hash, when the in-code default value is a Hash, or as a
      # JSON array, returned as an Array, when it is an Array.
      #
      # @return [OpenFeature::SDK::Provider::ResolutionDetails]
      def fetch_object_value(flag_key:, default_value:, evaluation_context: nil)
        @flag_reader.read(flag_key, default_value, evaluation_context)
      end

      private

      def initialize_the_client
        @client.init
      rescue StandardError => e
        emit_event(ProviderEvent::PROVIDER_ERROR, error_code: ErrorCode::GENERAL, message: e.message)
        raise
      end

      def send_the_report(report)
        case report
        when :report_ready then emit_event(ProviderEvent::PROVIDER_READY)
        when :report_the_failure then report_no_config_in_time
        when :nothing then nil
        end
      end

      def report_no_config_in_time
        emit_event(ProviderEvent::PROVIDER_ERROR, error_code: ErrorCode::PROVIDER_NOT_READY, message: NO_CONFIG_IN_TIME)
        send_the_report(@startup.report_due_after_the_failure)
        raise ::OpenFeature::SDK::EvaluationError.new(NO_CONFIG_IN_TIME, error_code: ErrorCode::PROVIDER_NOT_READY)
      end

      def report_the_configs_changed_by(update)
        emit_event(ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, flags_changed: [*update.keys, *update.removed_keys])
      end

      def value_of(tracking_event_details)
        tracking_event_details&.value
      end

      def details_of(tracking_event_details)
        attributes = tracking_event_details&.fields
        attributes.nil? || attributes.empty? ? nil : attributes
      end
    end
  end
end
