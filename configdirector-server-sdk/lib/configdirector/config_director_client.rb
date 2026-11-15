# frozen_string_literal: true

require "monitor"

module ConfigDirector
  # The ConfigDirector SDK client. Create one with {ConfigDirector.create_client}, call {#init} when your
  # application starts and {#close} when it shuts down. A client can be shared between threads.
  class ConfigDirectorClient
    WHAT_FOLLOWS_AN_INIT_WITHOUT_VALUES_BY_MODE = {
      "streaming" => "The client will continue to retry since there were no fatal errors detected. " \
                     "Configs will return the in-code default value until the connection succeeds.",
      "polling" => "Since the client was configured without streaming, configs may not update and always " \
                   "return the in-code default value.",
      "offline" => "The offline values were not delivered, so configs return the in-code default value."
    }.freeze

    private_constant :WHAT_FOLLOWS_AN_INIT_WITHOUT_VALUES_BY_MODE

    # @api private
    def initialize(connection:, connection_options:, metadata:, logger:, hooks:)
      @connection = connection
      @mode = connection_options.mode
      @timeout = connection_options.timeout.to_f
      @log = Internal::Logging::ClientLog.new(logger)
      @connection_lifecycle = Monitor.new
      @connection_opened = false
      @serving_state = Internal::Client::ServingState.new(metadata)
      @event_handlers = Internal::Client::EventHandlers.new(hooks, @log)
      @watches = Internal::Client::Watches.new(@log)
      @config_reader = Internal::Client::ConfigReader.new(@serving_state, @event_handlers, @log)
    end

    # Connects to ConfigDirector and makes the client ready. It waits, up to the connection timeout, for the
    # first values and for their +configs_updated+ handlers, watches and +client_ready+ handlers to finish.
    # Calling it again waits again and never opens a second connection.
    #
    # It never raises because the connection failed, and every read returns its in-code default value until
    # values arrive:
    #
    # - When no values arrive in time it logs a warning and returns, and the client keeps trying.
    # - When ConfigDirector refuses the connection, for example because it does not know the server SDK key,
    #   it logs an error, calls the +connection_error+ handlers and returns at once. The client does not try
    #   again, and a later call returns at once.
    # - In polling mode, when the first request for values fails for another reason, it logs an error and
    #   returns at once, and the client asks again after the polling interval.
    #
    # In offline mode it makes no network call and the client is ready when it returns.
    #
    # @return [void]
    # @raise [ConfigDirectorValidationError] when the client is closed
    def init
      give_up_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
      connection_opening = @connection_lifecycle.synchronize do
        raise_if_closed
        open_the_connection_once
      end

      case connection_opening
      when :first_attempt_failed then nil
      when :values_awaited, :opened_before
        warn_that_no_values_arrived_in_time if @serving_state.timed_out_waiting_for_the_first_values?(give_up_at)
      end
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
    # served, its value ID and its variation. Like every read, it calls the +config_evaluated+ handlers
    # before it returns.
    #
    # @param config_key [String] the config key to evaluate
    # @param default_value [Boolean, String, Integer, Float, Hash, Array] the in-code default value, returned
    #   when no value from ConfigDirector can be served. Its class decides the class of the value returned.
    # @param context [Context, nil] the context to evaluate the targeting rules for
    # @return [ConfigEvaluation] the evaluation, whose +value+ is what {#get_value} returns
    # @raise [ConfigDirectorValidationError] when the in-code default value is +nil+ or of any other class,
    #   or when the context is not a {Context}
    def evaluate(config_key, default_value, context = nil)
      @config_reader.read(@config_reader.config_read_of(config_key, default_value, context))
    end

    # Returns what every config serves to the given context, keyed by config key, or only the configs listed
    # in +config_keys+. It records no telemetry, calls no +config_evaluated+ handler, and returns an empty
    # Hash when the client is not ready.
    #
    # @param context [Context, nil] the context to evaluate the targeting rules for
    # @param config_keys [Array<String>, nil] the config keys to return. Every config is returned when left
    #   out.
    # @return [Hash{String => ConfigState}] what each config serves, keyed by config key
    # @raise [ConfigDirectorValidationError] when the context is not a {Context} or +config_keys+ is not an
    #   Array
    def get_all_configs(context: nil, config_keys: nil)
      @config_reader.states(context, config_keys)
    end

    # Calls the block with the config's value each time the client receives values that include the config
    # or leave it out, even when its value is the same. The block is not called when the watch is
    # registered, so a watch registered before {#init} receives the first value during it. When the values
    # received leave the config out, the block receives the in-code default value. The block is also called
    # each time the client receives a segment that one of the config's targeting rules uses. The block runs
    # on the thread that received the values, as {#on} describes, after the +configs_updated+ handlers, and
    # an error it raises is logged and ignored.
    #
    # @example
    #   subscription = client.watch("new-checkout", false, ConfigDirector::Context.new(id: "user-123")) do |enabled|
    #     puts "new-checkout is now #{enabled}"
    #   end
    #   subscription.close
    #
    # @param config_key [String] the config key to watch
    # @param default_value [Boolean, String, Integer, Float, Hash, Array] the in-code default value, as
    #   {#get_value} takes it. Its class decides the class of the value the block receives.
    # @param context [Context, nil] the context to evaluate the targeting rules for
    # @yieldparam value [Boolean, String, Integer, Float, Hash, Array] the config's value, or the in-code
    #   default value
    # @return [Subscription] the watch, which {Subscription#close} removes
    # @raise [ConfigDirectorValidationError] when no block is given, when the in-code default value is +nil+
    #   or of any other class, or when the context is not a {Context}
    def watch(config_key, default_value, context = nil, &callback)
      config_read = @config_reader.config_read_of(config_key, default_value, context)
      raise ConfigDirectorValidationError, "A watch needs a block to call with the value." if callback.nil?

      @watches.add(config_read, callback)
    end

    # Removes the first watch on the config key whose block is +callback+, or every watch on the config key
    # when +callback+ is left out. A block is found when it is the same Proc or lambda, such as one given
    # to {#watch} as +&on_change+. To remove one watch whatever its block, close the {Subscription}
    # {#watch} returned.
    #
    # @param config_key [String] the config key the watch is on
    # @param callback [Proc, nil] the block of the watch to remove
    # @return [void]
    def unwatch(config_key, callback = nil)
      @watches.remove(config_key, callback)
    end

    # Removes every watch on every config key.
    #
    # @return [void]
    def unwatch_all
      @watches.remove_all
    end

    # Registers a handler for one of the events the client emits. A handler registered twice runs twice.
    #
    # - +:client_ready+ handlers are called with no argument once, when the client first receives values
    #   and becomes ready, after the +configs_updated+ handlers and the watches.
    # - +:configs_updated+ handlers are called with a {ConfigsUpdatedEvent} each time the client receives
    #   values, the first time included.
    # - +:config_evaluated+ handlers are called with a {ConfigEvaluatedEvent} each time {#get_value},
    #   {#evaluate} or a watch evaluates a config, on the thread that read, before the read returns.
    # - +:connection_error+ handlers are called with a {ConnectionErrorEvent} when ConfigDirector refuses the
    #   connection, for example because it does not know the server SDK key, and the client will not try
    #   again. They are called at most once for a client.
    #
    # +client_ready+, +configs_updated+ and +connection_error+ handlers run on the thread that received
    # from ConfigDirector. In streaming mode that is a thread of the SDK. In polling mode it is the thread
    # that called {#init} for the first request, and a thread of the SDK for every later one. In offline
    # mode it is the thread that called {#init}. Handlers may read from the client, and an error a handler
    # raises is logged and ignored.
    #
    # @example
    #   client.on(:configs_updated) { |event| puts "Updated: #{event.keys.join(", ")}" }
    #
    # @param event_name [Symbol] +:client_ready+, +:configs_updated+, +:config_evaluated+ or
    #   +:connection_error+
    # @param handler [#call, nil] the handler, when no block is given: any object that responds to +call+,
    #   such as a lambda or +method(:name)+
    # @yield the event, as +handler+ would receive it
    # @return [Subscription] the registration, which {Subscription#close} removes
    # @raise [ConfigDirectorValidationError] when the event name is not one of the four Symbols, when both a
    #   handler and a block are given or neither is, or when the handler does not respond to +call+
    def on(event_name, handler = nil, &block)
      @event_handlers.add(event_name, Internal::Client::EventHandlers.one_handler_of(handler, block))
    end

    # Removes the first registration of +handler+ for the event, or every handler of the event, hooks
    # included, when +handler+ is left out. A handler is found when it is equal to +handler+, so
    # +method(:name)+ finds a handler registered as +method(:name)+, while a block or lambda is found only
    # as the same object.
    #
    # @param event_name [Symbol] +:client_ready+, +:configs_updated+, +:config_evaluated+ or
    #   +:connection_error+
    # @param handler [#call, nil] the handler to remove
    # @return [void]
    # @raise [ConfigDirectorValidationError] when the event name is not one of the four Symbols
    def off(event_name, handler = nil)
      @event_handlers.remove(event_name, handler)
    end

    # Closes the client and removes every handler, hook and watch. Afterwards the client is not ready, every
    # read returns its in-code default value and {#get_all_configs} is empty. It is safe to call more than
    # once.
    #
    # @return [void]
    def close
      @connection_lifecycle.synchronize do
        return if closed?

        @serving_state.close
        @event_handlers.remove_all
        @watches.remove_all
        @connection.close if @connection_opened
      end

      @log.debug { "close has been called, the client is now closed" }
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
      return :opened_before if @connection_opened

      @connection_opened = true
      intake = Internal::Client::ConnectionIntake.new(
        serving_state: @serving_state, event_handlers: @event_handlers, watches: @watches,
        config_reader: @config_reader, log: @log
      )
      report_unrecoverable_error = ->(connection_error) { intake.take_in_unrecoverable_error(connection_error) }
      @connection.open(report_unrecoverable_error: report_unrecoverable_error) { |payload| intake.take_in(payload) }
    end

    def warn_that_no_values_arrived_in_time
      @log.warn(
        "Timed out waiting for initialization after #{format("%g", @timeout)}s. " \
        "#{WHAT_FOLLOWS_AN_INIT_WITHOUT_VALUES_BY_MODE.fetch(@mode)}"
      )
    end
  end
end
