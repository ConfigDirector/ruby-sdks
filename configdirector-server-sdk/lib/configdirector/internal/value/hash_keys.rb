# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Value
      module HashKeys
        def self.name_of(given_key)
          case given_key
          when String then given_key
          when Symbol then given_key.name
          end
        end

        def self.description_of_a_key_given_twice_in(given_keys, key_texts)
          key_text_given_twice = key_texts.tally.find { |_key_text, count| count > 1 }&.first
          return nil if key_text_given_twice.nil?

          first_given, second_given = given_keys.zip(key_texts)
                                                .select { |_given_key, key_text| key_text == key_text_given_twice }
                                                .map(&:first)
          "'#{key_text_given_twice}' is given twice, #{how_the_two_keys_differ(first_given, second_given)}"
        end

        def self.how_the_two_keys_differ(first_given, second_given)
          return "in two encodings" if first_given.instance_of?(second_given.class)

          "as a #{first_given.class} and as a #{second_given.class}"
        end

        private_class_method :how_the_two_keys_differ
      end
    end
  end
end
