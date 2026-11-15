# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Value
      EncodedNativeValue = Data.define(:config_type, :served_text)

      class EncodedNativeValue
        def self.of(value, config_key)
          case value
          when true then new(config_type: "boolean", served_text: "true")
          when false then new(config_type: "boolean", served_text: "false")
          when Integer then new(config_type: "integer", served_text: value.to_s)
          when Float then encoded_float(value, config_key)
          when String then new(config_type: "string", served_text: utf8_text_of(value, config_key))
          when Hash, Array then new(config_type: "json", served_text: JsonContents.json_text_of(value, config_key))
          else raise unservable_because_of_the_class_of(value, config_key)
          end
        end

        def self.encoded_float(value, config_key)
          unless value.finite?
            raise UnservableValue, "Invalid value for '#{config_key}': #{value} is not a finite number."
          end

          new(config_type: "float", served_text: PlainDecimalText.of(value))
        end

        def self.utf8_text_of(value, config_key)
          utf8_text = Utf8Text.of(value)
          return utf8_text unless utf8_text.nil?

          raise UnservableValue, "Invalid value for '#{config_key}': the String is not valid UTF-8 text."
        end

        def self.unservable_because_of_the_class_of(value, config_key)
          UnservableValue.new(
            "Invalid value for '#{config_key}': #{value.nil? ? "nil" : "an object of class #{value.class}"}. " \
            "Use true or false, an Integer, a Float, a String, a Hash or an Array."
          )
        end

        private_class_method :encoded_float, :utf8_text_of, :unservable_because_of_the_class_of
      end
    end
  end
end
