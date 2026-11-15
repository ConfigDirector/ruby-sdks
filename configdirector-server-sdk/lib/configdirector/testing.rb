# frozen_string_literal: true

require_relative "../configdirector"
require_relative "internal/connection/test_client_values"
require_relative "internal/connection/test_client_initializations"
require_relative "internal/connection/payloads_delivered_in_turn"
require_relative "internal/connection/in_memory_connection"
require_relative "testing/test_client"

module ConfigDirector
  # The testing tools of the ConfigDirector server SDK, loaded with <tt>require "configdirector/testing"</tt>.
  module Testing
    # Creates a {TestClient}: the SDK's real client over an in-memory connection that the test controls. It needs
    # no server SDK key, never connects to ConfigDirector, starts no thread and sends nothing.
    #
    # @example
    #   require "configdirector/testing"
    #
    #   test_client = ConfigDirector::Testing.create_test_client({ "new-checkout" => true })
    #   service = CheckoutService.new(test_client.client)
    #   test_client.client.init
    #
    #   expect(service.new_checkout_enabled?("user-123")).to be(true)
    #
    #   test_client.set_value("new-checkout", false)
    #   expect(service.new_checkout_enabled?("user-123")).to be(false)
    #
    # @param values [Hash{String, Symbol => Boolean, Integer, Float, String, Hash, Array}, nil] the values to
    #   serve, keyed by config key, as {TestClient#set_value} takes them. Defaults to none.
    # @param timeout [Integer, Float, nil] how long an +init+ that {TestClient#hold_initialization} held waits, in
    #   seconds. Defaults to 3 seconds, the timeout of a production client.
    # @param logger [#debug, #info, #warn, #error, nil] a logger with the methods of Ruby's +Logger+, as
    #   {ConfigDirector.create_client} takes it. Without one the SDK writes warnings and errors to standard error.
    # @return [TestClient] a test client whose client is not initialized yet
    # @raise [ConfigDirectorValidationError] when +values+ is not a Hash or holds a key or a value the SDK cannot
    #   serve, as {TestClient#set_value} describes; when +timeout+ is not a positive number; or when the +logger+
    #   lacks one of the four methods
    def self.create_test_client(values = nil, timeout: nil, logger: nil)
      Internal::Client::ClientFactory.test_client_serving(values, timeout: timeout, logger: logger)
    end
  end
end
