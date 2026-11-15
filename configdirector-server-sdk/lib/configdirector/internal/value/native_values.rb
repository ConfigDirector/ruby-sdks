# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Value
      module NativeValues
        def self.config_keys_of(values)
          given_keys = values.keys
          config_keys = given_keys.map { |given_key| config_key_named_by(given_key) }
          key_given_twice = HashKeys.description_of_a_key_given_twice_in(given_keys, config_keys)
          raise UnservableValue, "The config key #{key_given_twice}." unless key_given_twice.nil?

          config_keys
        end

        def self.config_key_named_by(given_key)
          key_name = HashKeys.name_of(given_key)
          if key_name.nil?
            raise UnservableValue,
                  "Invalid config key of class #{given_key.class}. A config key must be a String or a Symbol."
          end
          config_key = Utf8Text.of(key_name)
          raise UnservableValue, "Invalid config key. The key of a value is not valid UTF-8 text." if config_key.nil?
          raise UnservableValue, "Invalid config key. The key of a value cannot be empty." if config_key.strip.empty?

          config_key
        end

        private_class_method :config_key_named_by
      end
    end
  end
end
