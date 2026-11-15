# frozen_string_literal: true

require "pathname"

module ConfigDirector
  module Internal
    module Connection
      class OfflineModeConnection
        CONFIG_ID_PREFIX = "offline:"

        private_constant :CONFIG_ID_PREFIX

        def self.for_a_client_with(connection_options:, **)
          file = connection_options.file
          values = connection_options.values

          case offline_source_given_by(file, values)
          when :no_values then serving_the_payload(ServerSdkPayload.without_definitions)
          when :values then serving_the_payload(payload_serving_the_given_values(values))
          when :file then reading_the_file(file)
          when :file_and_values
            raise ConfigDirectorValidationError, "An offline connection takes either 'file' or 'values', not both."
          end
        end

        def self.offline_source_given_by(file, values)
          if file.nil? && values.nil? then :no_values
          elsif file.nil? then :values
          elsif values.nil? then :file
          else :file_and_values
          end
        end

        def self.serving_the_payload(payload)
          new(-> { payload })
        end

        def self.reading_the_file(file)
          unless file.is_a?(String) || file.is_a?(Pathname)
            raise ConfigDirectorValidationError,
                  "Invalid 'file' option of class #{file.class}. It must be a String or a Pathname."
          end

          new(-> { payload_serving_the_values_in_the_file(file) })
        end

        def self.payload_serving_the_given_values(values)
          Value::NativeValues.reject_values_of_another_class(values)
          payload_serving(values)
        rescue Value::UnservableValue => e
          raise ConfigDirectorValidationError, "The offline values could not be loaded. #{e.message}"
        end

        def self.payload_serving_the_values_in_the_file(file)
          payload_serving(OfflineValuesFile.values_in(file))
        rescue Value::UnservableValue => e
          raise ConfigDirectorInitializationError, "The offline values file '#{file}' could not be loaded. #{e.message}"
        end

        def self.payload_serving(values)
          ServerSdkPayload.of_definitions(
            ConfigDefinition.serving_each_value_to_every_context(values, CONFIG_ID_PREFIX)
          )
        end

        private_class_method :new, :offline_source_given_by, :serving_the_payload, :reading_the_file,
                             :payload_serving_the_given_values, :payload_serving_the_values_in_the_file,
                             :payload_serving

        def initialize(payload_of_the_offline_values)
          @payload_of_the_offline_values = payload_of_the_offline_values
          @delivering_the_offline_values = false
        end

        def open(**, &)
          deliver_the_offline_values(&) unless @delivering_the_offline_values

          :values_awaited
        end

        def restart_in_a_forked_process(**); end

        def close; end

        private

        def deliver_the_offline_values
          @delivering_the_offline_values = true
          yield @payload_of_the_offline_values.call
        ensure
          @delivering_the_offline_values = false
        end
      end
    end
  end
end
