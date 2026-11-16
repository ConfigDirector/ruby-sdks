# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      module ReportedValue
        MAXIMUM_CHARACTERS_REPORTED_AS_TEXT = 500
        JSON_CONFIG_TYPE = "json"

        private_constant :MAXIMUM_CHARACTERS_REPORTED_AS_TEXT, :JSON_CONFIG_TYPE

        def self.reported_by_the_value_id_sent_with_it?(value, config_type, value_id_sent_with_the_value)
          return false if value_id_sent_with_the_value.nil?

          json_value?(value, config_type) ||
            (value.is_a?(String) && value.length > MAXIMUM_CHARACTERS_REPORTED_AS_TEXT)
        end

        def self.of(value, config_type)
          return { valueId: ValueId.of(CompactJsonText.of(value)) } if json_value?(value, config_type)

          text = ReportedText.of(Evaluation::ScalarText.of(value).to_s)

          text.length <= MAXIMUM_CHARACTERS_REPORTED_AS_TEXT ? { value: text } : { valueId: ValueId.of(text) }
        end

        def self.json_value?(value, config_type)
          config_type == JSON_CONFIG_TYPE || value.is_a?(Hash) || value.is_a?(Array)
        end

        private_class_method :json_value?
      end
    end
  end
end
