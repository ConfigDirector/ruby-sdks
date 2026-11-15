# frozen_string_literal: true

module ConfigDirector
  module Testing
    # The SDK's real client over an in-memory connection that the test controls. Create one with
    # {Testing.create_test_client}.
    #
    # The client under {#client} is the SDK's production client: reading values, watches, events and readiness
    # behave as they do against ConfigDirector. Only the connection is replaced, so no request is made, no thread
    # is started and nothing is sent.
    #
    # While the client is connected, every change this test client makes reaches it before the call returns: the
    # +configs_updated+ handlers and the watches run on the calling thread, inside the call, so an assertion can
    # follow it directly. A change made from inside a handler or a watch reaches the client right after the change
    # being handled. The client is connected from an +init+ that serves the values, or a
    # {#complete_initialization}, until its +close+ or an +init+ that is held or fails. A change made while it is
    # not connected is stored, and reaches it with the next +init+ that serves the values.
    class TestClient
      # @return [ConfigDirectorClient] the SDK client to hand to the code under test. It starts not ready, like a
      #   production client, and its +init+ serves the stored values at once unless initialization is held or set
      #   to fail. Each later +init+ serves the stored values again, as a full update. Close it with +close+ when
      #   the test ends; the test client has no +close+ of its own.
      attr_reader :client

      # @api private
      def initialize(client, connection)
        @client = client
        @connection = connection
      end

      # Stores a value under a config key and, while the client is connected, delivers an update that carries only
      # that key, so reads, the key's watches and the +configs_updated+ handlers see it. The update names the key
      # even when the value is the one it already has.
      #
      # The config type follows from the class of the value: +true+ or +false+ is a boolean config, an Integer an
      # integer config, a Float a float config, a String a string config, and a Hash or an Array a JSON config,
      # which can hold +nil+. Every context receives the same value, as a match (+"found-match"+) with no value
      # ID and no variation, from a config whose ID is +test-config:+ followed by the key.
      #
      # @param config_key [String, Symbol] the config key. A Symbol is read as its name.
      # @param value [Boolean, Integer, Float, String, Hash, Array] the value to serve
      # @return [void]
      # @raise [ConfigDirectorValidationError] when the key is blank, of another class or not UTF-8 text, or the
      #   value is one the SDK cannot serve, such as +nil+, a Symbol or a Float that is not finite. Nothing changes
      #   then.
      def set_value(config_key, value)
        @connection.set_value(config_key, value)
      end

      # Removes the value of a config key and, while the client is connected, delivers a full update of the values
      # left: reads of the key return their in-code default value with +"config-state-missing"+, the key's
      # watches receive that in-code default value, and the +configs_updated+ handlers find the key in
      # +removed_keys+ and every key left in +keys+. A key that holds no value removes nothing, and the full
      # update is still delivered.
      #
      # @param config_key [String, Symbol] the config key. A Symbol is read as its name.
      # @return [void]
      # @raise [ConfigDirectorValidationError] when the key is neither a String nor a Symbol
      def remove_value(config_key)
        @connection.remove_value(config_key)
      end

      # Replaces every stored value, cancels a {#hold_initialization} or {#fail_initialization} that no +init+
      # has used yet, and, while the client is connected, delivers the new values as a full update. Use it to
      # reset a test client shared between tests.
      #
      # @param values [Hash{String, Symbol => Boolean, Integer, Float, String, Hash, Array}] the values to serve
      #   from now on, keyed by config key, as {#set_value} takes them
      # @return [void]
      # @raise [ConfigDirectorValidationError] when +values+ is not a Hash, or as {#set_value} raises. Nothing
      #   changes then.
      def replace_values(values)
        @connection.replace_values(values)
      end

      # Makes the next +init+ wait until another thread calls {#complete_initialization} or
      # {#fail_initialization}, or until the client's timeout. At the timeout +init+ logs the warning a production
      # client logs when no values arrive in time and returns: a client that was not ready stays not ready, so
      # reads return their in-code default value with +"client-not-ready"+, and one that was ready keeps serving
      # the values it had, without the warning. A +close+ or an +init+ called meanwhile, from another thread or
      # from a handler that {#complete_initialization} or {#fail_initialization} runs, returns once that held
      # +init+ returns.
      #
      # @return [void]
      def hold_initialization
        @connection.hold_initialization
      end

      # Delivers the stored values to an +init+ that {#hold_initialization} held, on the calling thread: the
      # +configs_updated+ handlers receive every config key, then the watches run, then the +client_ready+
      # handlers if the client was not ready. The client is ready when this returns, and the held +init+
      # returns once those handlers and watches have run. Called before +init+ while a hold is set, it cancels
      # the hold instead. Otherwise it does nothing.
      #
      # @return [void]
      def complete_initialization
        @connection.complete_initialization
      end

      # Fails an +init+ that {#hold_initialization} held, on the calling thread, or makes the next +init+ fail.
      # An error is logged, the +connection_error+ handlers receive a {ConfigDirectorConnectionError} with the
      # status 401, and the failed +init+ returns once they have run. A client that was not ready stays not ready,
      # and one that was ready keeps serving the values it had. The +init+ after a failed one serves the stored
      # values.
      #
      # @return [void]
      def fail_initialization
        @connection.fail_initialization
      end
    end
  end
end
