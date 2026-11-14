# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      module ContextAttributes
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
          return with_symbols_as_text(traits) if traits.nil? || traits.is_a?(Hash)

          raise ConfigDirectorValidationError,
                "Invalid context traits of class #{traits.class}. A context's traits must be a Hash."
        end

        def self.anonymous_flag(anonymous)
          return anonymous if [true, false].include?(anonymous)

          raise ConfigDirectorValidationError,
                "Invalid anonymous flag of class #{anonymous.class}. A context's anonymous flag must be true or false."
        end

        def self.with_symbols_as_text(trait)
          case trait
          when Hash then trait.to_h { |key, value| [text_of_a_symbol(key), with_symbols_as_text(value)] }.freeze
          when Array then trait.map { |element| with_symbols_as_text(element) }.freeze
          else UnchangeableCopy.of(text_of_a_symbol(trait))
          end
        end

        def self.text_of_a_symbol(key_or_value)
          key_or_value.is_a?(Symbol) ? key_or_value.name : key_or_value
        end

        private_class_method :with_symbols_as_text, :text_of_a_symbol
      end
    end
  end
end
