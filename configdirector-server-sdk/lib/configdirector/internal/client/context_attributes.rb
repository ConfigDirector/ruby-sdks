# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      module ContextAttributes
        MOST_LEVELS_OF_TRAITS = 100

        private_constant :MOST_LEVELS_OF_TRAITS

        def self.identifier_text(id)
          case id
          when nil then nil
          when String then UnchangeableCopy.of(id)
          when Integer then id.to_s.freeze
          else raise ConfigDirectorValidationError, "Invalid context id of class #{id.class}. " \
                                                    "A context's id must be a String or an Integer."
          end
        end

        def self.name_text(name)
          return UnchangeableCopy.of(name) if name.nil? || name.is_a?(String)

          raise ConfigDirectorValidationError,
                "Invalid context name of class #{name.class}. A context's name must be a String."
        end

        def self.traits_with_symbols_as_text(traits)
          return with_symbols_as_text(traits, 1) if traits.nil? || traits.is_a?(Hash)

          raise ConfigDirectorValidationError,
                "Invalid context traits of class #{traits.class}. A context's traits must be a Hash."
        end

        def self.anonymous_flag(anonymous)
          return anonymous if [true, false].include?(anonymous)

          raise ConfigDirectorValidationError,
                "Invalid anonymous flag of class #{anonymous.class}. A context's anonymous flag must be true or false."
        end

        def self.with_symbols_as_text(trait, level)
          case trait
          when Hash, Array then container_with_symbols_as_text(trait, level)
          else UnchangeableCopy.of(text_of_a_symbol(trait))
          end
        end

        def self.container_with_symbols_as_text(container, level)
          raise traits_nested_too_deep if level > MOST_LEVELS_OF_TRAITS

          level_of_its_contents = level + 1
          case container
          when Hash
            container.to_h do |key, value|
              [text_of_a_symbol(key), with_symbols_as_text(value, level_of_its_contents)]
            end.freeze
          else container.map { |element| with_symbols_as_text(element, level_of_its_contents) }.freeze
          end
        end

        def self.traits_nested_too_deep
          ConfigDirectorValidationError.new(
            "Invalid context traits nested deeper than #{MOST_LEVELS_OF_TRAITS} levels. A context's traits must be " \
            "nested #{MOST_LEVELS_OF_TRAITS} levels deep or less, so a Hash or an Array among them cannot hold itself."
          )
        end

        def self.text_of_a_symbol(key_or_value)
          key_or_value.is_a?(Symbol) ? key_or_value.name : key_or_value
        end

        private_class_method :with_symbols_as_text, :container_with_symbols_as_text, :traits_nested_too_deep,
                             :text_of_a_symbol
      end
    end
  end
end
