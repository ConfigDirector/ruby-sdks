# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Value
      module NativeValues
        def self.reject_values_of_another_class(values)
          return if values.is_a?(Hash)

          raise ConfigDirectorValidationError, "Invalid 'values' option of class #{values.class}. It must be a Hash."
        end

        def self.config_keys_of(values)
          given_keys = values.keys
          config_keys = given_keys.map { |given_key| config_key_named_by(given_key) }
          key_given_twice = HashKeys.description_of_a_key_given_twice_in(given_keys, config_keys)
          raise UnservableValue, "The config key #{key_given_twice}." unless key_given_twice.nil?

          config_keys
        end

        def self.name_of_a_config_key(given_key)
          key_name = HashKeys.name_of(given_key)
          return key_name unless key_name.nil?

          raise UnservableValue,
                "Invalid config key of class #{given_key.class}. A config key must be a String or a Symbol."
        end

        def self.config_key_named_by(given_key)
          config_key = Utf8Text.of(name_of_a_config_key(given_key))
          raise UnservableValue, "Invalid config key. The key of a value is not valid UTF-8 text." if config_key.nil?
          raise UnservableValue, "Invalid config key. The key of a value cannot be empty." if config_key.strip.empty?

          config_key
        end

        private_class_method :config_key_named_by
      end
    end
  end
end
