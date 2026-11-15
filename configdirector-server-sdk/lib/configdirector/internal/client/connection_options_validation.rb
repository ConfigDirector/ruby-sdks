# frozen_string_literal: true

require "uri"

module ConfigDirector
  module Internal
    module Client
      module ConnectionOptionsValidation
        SOURCE_OF_VALUES_BY_MODE = {
          "streaming" => :configdirector,
          "polling" => :configdirector,
          "offline" => :offline_values
        }.freeze

        private_constant :SOURCE_OF_VALUES_BY_MODE

        def self.reject_unusable(connection, server_sdk_key)
          reject_an_unknown_mode(connection.mode)
          case SOURCE_OF_VALUES_BY_MODE.fetch(connection.mode)
          when :configdirector then reject_an_unusable_connection_to_configdirector(connection, server_sdk_key)
          when :offline_values then reject_an_offline_timeout_that_is_not_a_number(connection.timeout)
          end
          return if NumberOfSeconds.finite?(connection.polling_interval)

          raise ConfigDirectorValidationError,
                "Invalid polling interval '#{connection.polling_interval}'. " \
                "The polling interval must be a number of seconds."
        end

        def self.reject_an_unknown_mode(mode)
          return if SOURCE_OF_VALUES_BY_MODE.key?(mode)

          raise ConfigDirectorValidationError,
                "Unknown connection mode #{mode.inspect}. " \
                "Expected one of: #{SOURCE_OF_VALUES_BY_MODE.keys.map(&:inspect).join(", ")}."
        end

        def self.reject_an_unusable_connection_to_configdirector(connection, server_sdk_key)
          reject_an_unusable_server_sdk_key(server_sdk_key)
          reject_offline_values_given_to(connection)
          reject_an_unusable_url(connection.url)
          reject_a_timeout_that_is_not_positive(connection.timeout)
        end

        def self.reject_a_timeout_that_is_not_positive(timeout)
          return if NumberOfSeconds.finite_and_positive?(timeout)

          raise ConfigDirectorValidationError,
                "Invalid timeout '#{timeout}'. The timeout must be a positive number of seconds."
        end

        def self.reject_an_offline_timeout_that_is_not_a_number(timeout)
          return if NumberOfSeconds.finite?(timeout)

          raise ConfigDirectorValidationError, "Invalid timeout '#{timeout}'. The timeout must be a number of seconds."
        end

        def self.reject_an_unusable_server_sdk_key(server_sdk_key)
          return if server_sdk_key.is_a?(String) && !server_sdk_key.strip.empty?

          raise ConfigDirectorValidationError,
                "No server SDK key was provided, the client cannot be instantiated without a valid server SDK key"
        end

        def self.reject_offline_values_given_to(connection)
          return if connection.file.nil? && connection.values.nil?

          raise ConfigDirectorValidationError,
                "The connection options 'file' and 'values' apply only when the connection mode is 'offline', " \
                "but the mode is '#{connection.mode}'."
        end

        def self.reject_an_unusable_url(url)
          return if http_url?(url)

          raise ConfigDirectorValidationError, "Invalid base URL '#{url}'. The base URL must be an http or https URL."
        end

        def self.http_url?(url)
          return false unless url.is_a?(String)

          uri = URI.parse(url)
          uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
        rescue URI::InvalidURIError
          false
        end

        private_class_method :reject_an_unknown_mode, :reject_an_unusable_connection_to_configdirector,
                             :reject_an_offline_timeout_that_is_not_a_number, :reject_an_unusable_server_sdk_key,
                             :reject_offline_values_given_to, :reject_an_unusable_url, :http_url?
      end
    end
  end
end
