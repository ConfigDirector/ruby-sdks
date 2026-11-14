# frozen_string_literal: true

require "json"

module ConfigDirector
  module Internal
    module Value
      module ServedText
        CONFIG_TYPES_NOT_READABLE_AS_A_STRING = %w[boolean integer float].freeze
        WHOLE_NUMBER_DIGITS = /\A[+-]?[0-9]+\z/

        def self.typed_as(in_code_default_value_kind, served_text, config_type)
          return "value-missing" if served_text.nil? || served_text.empty?

          TYPED_BY_IN_CODE_DEFAULT_VALUE_KIND.fetch(in_code_default_value_kind).call(served_text, config_type)
        end

        def self.boolean_in(served_text)
          case served_text.downcase
          when "true" then TypedValue.new(value: true)
          when "false" then TypedValue.new(value: false)
          else "invalid-boolean"
          end
        end

        def self.string_of(served_text, config_type)
          return "type-mismatch" if CONFIG_TYPES_NOT_READABLE_AS_A_STRING.include?(config_type)

          TypedValue.new(value: served_text)
        end

        def self.whole_number_in(served_text)
          return TypedValue.new(value: Integer(served_text, 10)) if served_text.match?(WHOLE_NUMBER_DIGITS)

          finite_number = Evaluation::NumberComparison.finite_number_in(served_text)
          return "invalid-number" if finite_number.nil? || finite_number != finite_number.floor

          TypedValue.new(value: finite_number.to_i)
        end

        def self.finite_number_in(served_text)
          finite_number = Evaluation::NumberComparison.finite_number_in(served_text)

          finite_number.nil? ? "invalid-number" : TypedValue.new(value: finite_number)
        end

        def self.json_in(served_text, json_class)
          parsed = JSON.parse(served_text, allow_duplicate_key: true)

          parsed.is_a?(json_class) ? TypedValue.new(value: parsed) : "invalid-json"
        rescue JSON::ParserError
          "invalid-json"
        end

        private_class_method :boolean_in, :string_of, :whole_number_in, :finite_number_in, :json_in

        TYPED_BY_IN_CODE_DEFAULT_VALUE_KIND = {
          boolean: ->(served_text, _config_type) { boolean_in(served_text) },
          string: ->(served_text, config_type) { string_of(served_text, config_type) },
          integer: ->(served_text, _config_type) { whole_number_in(served_text) },
          float: ->(served_text, _config_type) { finite_number_in(served_text) },
          json_object: ->(served_text, _config_type) { json_in(served_text, Hash) },
          json_array: ->(served_text, _config_type) { json_in(served_text, Array) }
        }.freeze

        private_constant :CONFIG_TYPES_NOT_READABLE_AS_A_STRING, :WHOLE_NUMBER_DIGITS,
                         :TYPED_BY_IN_CODE_DEFAULT_VALUE_KIND
      end
    end
  end
end
