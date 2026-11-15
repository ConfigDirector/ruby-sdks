# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      TestClientValues = Data.define(:configs)

      class TestClientValues
        CONFIG_ID_PREFIX = "test-config:"

        private_constant :CONFIG_ID_PREFIX

        def self.serving(values)
          Value::NativeValues.reject_values_of_another_class(values)
          new(
            configs: rejecting_what_cannot_be_served do
              ConfigDefinition.serving_each_value_to_every_context(values, CONFIG_ID_PREFIX)
            end
          )
        end

        def self.rejecting_what_cannot_be_served
          yield
        rescue Value::UnservableValue => e
          raise ConfigDirectorValidationError, e.message
        end

        def merged_with(values)
          with(configs: configs.merge(values.configs))
        end

        def without_the_value_of(given_key)
          key_name = TestClientValues.rejecting_what_cannot_be_served do
            Value::NativeValues.name_of_a_config_key(given_key)
          end

          case Value::Utf8Text.of(key_name)
          in String => config_key then with(configs: configs.except(config_key))
          in nil then self
          end
        end

        def full_payload
          ServerSdkPayload.of_definitions(configs)
        end

        def delta_payload
          ServerSdkPayload.delta_of_definitions(configs)
        end
      end
    end
  end
end
