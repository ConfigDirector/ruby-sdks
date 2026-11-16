# frozen_string_literal: true

require "json"

module ConfigDirector
  module Internal
    module Value
      module JsonContents
        MAXIMUM_NESTING = 100
        WHAT_JSON_CONTENTS_CAN_HOLD = "JSON contents can hold true and false, Integers, finite Floats, Strings, " \
                                      "nil, Arrays and Hashes with String or Symbol keys."

        private_constant :MAXIMUM_NESTING, :WHAT_JSON_CONTENTS_CAN_HOLD

        def self.json_text_of(json_value, config_key)
          JSON.generate(contents_at(JsonPosition.at_the_top_of(config_key), json_value))
        end

        def self.contents_at(position, contents)
          case contents
          when nil, true, false, Integer then contents
          when String then utf8_text_at(position, contents)
          when Float then finite_float_at(position, contents)
          when Array, Hash then container_contents_at(position, contents)
          else raise unservable_contents_at(position, "an object of class #{contents.class} cannot be encoded as JSON")
          end
        end

        def self.utf8_text_at(position, text)
          Utf8Text.of(text) || raise(position.unservable_because("the String is not valid UTF-8 text."))
        end

        def self.finite_float_at(position, float)
          raise unservable_contents_at(position, "#{float} is not a finite number") unless float.finite?

          float
        end

        def self.container_contents_at(position, container)
          if position.nesting > MAXIMUM_NESTING
            raise UnservableValue,
                  "Invalid value for '#{position.config_key}': nesting of #{position.nesting} is too deep."
          end

          case container
          when Array
            container.each_with_index.map { |element, index| contents_at(position.of_element(index), element) }
          else members_at(position, container)
          end
        end

        def self.members_at(position, json_object)
          given_keys = json_object.keys
          key_texts = given_keys.map { |given_key| key_text_at(position, given_key) }
          key_given_twice = HashKeys.description_of_a_key_given_twice_in(given_keys, key_texts)
          raise position.unservable_because("the key #{key_given_twice}.") unless key_given_twice.nil?

          key_texts.zip(json_object.values).to_h do |key_text, member|
            [key_text, contents_at(position.of_member(key_text), member)]
          end
        end

        def self.key_text_at(position, given_key)
          key_name = HashKeys.name_of(given_key)
          if key_name.nil?
            raise unservable_contents_at(position, "a key of class #{given_key.class} cannot be encoded as JSON")
          end

          Utf8Text.of(key_name) || raise(position.unservable_because("a key is not valid UTF-8 text."))
        end

        def self.unservable_contents_at(position, problem)
          position.unservable_because("#{problem}. #{WHAT_JSON_CONTENTS_CAN_HOLD}")
        end

        private_class_method :contents_at, :utf8_text_at, :finite_float_at, :container_contents_at, :members_at,
                             :key_text_at, :unservable_contents_at
      end
    end
  end
end
