# frozen_string_literal: true

module ConfigDirector
  # The ConfigDirector SDK client. Create one with {ConfigDirector.create_client}, call {#init} when your
  # application starts and {#close} when it shuts down. A client can be shared between threads.
  class ConfigDirectorClient
    LOG_PREFIX = "[ConfigDirectorClient]"

    private_constant :LOG_PREFIX

    # @api private
    def initialize(connection:, metadata:, timeout:, logger:)
      @connection = connection
      @metadata = metadata
      @timeout = timeout
      @logger = logger
      @logs_at_debug_level = logger.respond_to?(:debug?) ? logger.method(:debug?) : -> { true }
      @connection_lifecycle = Mutex.new
      @connection_opened = false
      @serving_state = Internal::Client::ServingState.new
      @context_admission = Internal::Client::ContextAdmission.new(logger)
    end

    # Gets the values ConfigDirector serves and makes the client ready. It waits for the first values, up to
    # the connection timeout. When no values arrive in time it logs a warning and returns, and every read
    # returns its in-code default value until values arrive. Calling it again waits again and never opens
    # a second connection.
    #
    # @return [void]
    # @raise [ConfigDirectorValidationError] when the client is closed
    def init
      @connection_lifecycle.synchronize do
        raise_if_closed
        open_the_connection_once
      end

      warn_that_no_values_arrived_in_time if @serving_state.timed_out_waiting_for_the_first_values?(@timeout)
    end

    # @return [Boolean] whether the client has values to serve
    def ready?
      !@serving_state.served_configs.nil?
    end

    # Evaluates a config and returns its value for the given context.
    #
    # @example
    #   client.get_value("new-checkout", false, ConfigDirector::Context.new(id: "user-123"))
    #
    # @param config_key [String] the config key to evaluate
    # @param default_value [Boolean, String, Integer, Float, Hash, Array] the in-code default value, returned
    #   when no value from ConfigDirector can be served: for example before the client is ready, when no
    #   config has the key, or when the config's value cannot be read as the class of this value. Its class
    #   decides the class of the value returned: +true+ or +false+ reads a boolean, a String reads the text
    #   of any config that is not a boolean, an integer or a float, an Integer reads a whole number, a Float
    #   reads a number, a Hash reads a JSON object and an Array reads a JSON array.
    # @param context [Context, nil] the context to evaluate the targeting rules for
    # @return [Boolean, String, Integer, Float, Hash, Array] the config's value, or the in-code default value
    # @raise [ConfigDirectorValidationError] when the in-code default value is +nil+ or of any other class,
    #   or when the context is not a {Context}
    def get_value(config_key, default_value, context = nil)
      evaluate(config_key, default_value, context).value
    end

    # Evaluates a config as {#get_value} does and returns the evaluation: the value, the reason it was
    # served, its value ID and its variation.
    #
    # @param config_key [String] the config key to evaluate
    # @param default_value [Boolean, String, Integer, Float, Hash, Array] the in-code default value, returned
    #   when no value from ConfigDirector can be served. Its class decides the class of the value returned.
    # @param context [Context, nil] the context to evaluate the targeting rules for
    # @return [ConfigEvaluation] the evaluation, whose +value+ is what {#get_value} returns
    # @raise [ConfigDirectorValidationError] when the in-code default value is +nil+ or of any other class,
    #   or when the context is not a {Context}
    def evaluate(config_key, default_value, context = nil)
      config_read = config_read_of(config_key, default_value, context)
      evaluation = @serving_state.served_configs&.evaluation(config_read) ||
                   config_read.in_code_default_evaluation("client-not-ready")
      log_at_debug_level do
        "#{LOG_PREFIX} Evaluated #{evaluation.key.inspect} to #{evaluation.value.inspect} (#{evaluation.reason})"
      end
      evaluation
    end

    # Returns what every config serves to the given context, keyed by config key, or only the configs listed
    # in +config_keys+. It records no telemetry, and returns an empty Hash when the client is not ready.
    #
    # @param context [Context, nil] the context to evaluate the targeting rules for
    # @param config_keys [Array<String>, nil] the config keys to return. Every config is returned when left
    #   out.
    # @return [Hash{String => ConfigState}] what each config serves, keyed by config key
    # @raise [ConfigDirectorValidationError] when the context is not a {Context} or +config_keys+ is not an
    #   Array
    def get_all_configs(context: nil, config_keys: nil)
      reject_config_keys_that_are_not_an_array(config_keys)
      admitted_context = @context_admission.admitted_context_or_none(context)

      @serving_state.served_configs&.states(admitted_context, config_keys) || {}
    end

    # Closes the client. Afterwards the client is not ready, every read returns its in-code default value
    # and {#get_all_configs} is empty. It is safe to call more than once.
    #
    # @return [void]
    def close
      @connection_lifecycle.synchronize do
        return if closed?

        @serving_state.close
        @connection.close if @connection_opened
      end

      log_at_debug_level { "#{LOG_PREFIX} close has been called, the client is now closed" }
    end

    # @return [Boolean] whether {#close} has been called
    def closed?
      @serving_state.closed?
    end

    private

    def raise_if_closed
      return unless closed?

      raise ConfigDirectorValidationError,
            "This client has been closed and can no longer be used. Create a new one instead."
    end

    def open_the_connection_once
      return if @connection_opened

      @connection.open { |payload| take_in(payload) }
      @connection_opened = true
    end

    def warn_that_no_values_arrived_in_time
      @logger.warn(
        "#{LOG_PREFIX} Timed out waiting for initialization after #{format("%g", @timeout)} seconds. " \
        "Configs return the in-code default value until values arrive."
      )
    end

    def take_in(payload)
      arrival = @serving_state.serve(Internal::Client::ServedConfigs.new(payload: payload, metadata: @metadata))
      return unless arrival == :first_values

      log_at_debug_level { "#{LOG_PREFIX} Received initial payload from the server, client is ready" }
    end

    def config_read_of(config_key, default_value, context)
      Internal::Client::ConfigRead.new(
        config_key: config_key,
        in_code_default_value: Internal::Value::InCodeDefaultValue.from(default_value),
        context: @context_admission.admitted_context_or_none(context)
      )
    end

    def reject_config_keys_that_are_not_an_array(config_keys)
      return if config_keys.nil? || config_keys.is_a?(Array)

      raise ConfigDirectorValidationError,
            "Invalid config keys of class #{config_keys.class}. The config keys must be an Array of Strings."
    end

    def log_at_debug_level
      @logger.debug(yield) if @logs_at_debug_level.call
    end
  end
end
