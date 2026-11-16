# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      class ReportedDetails
        MOST_TOP_LEVEL_KEYS = 20
        MOST_JSON_BYTES = 1_024
        MOST_VALUES_THE_JSON_BYTES_HOLD = MOST_JSON_BYTES

        private_constant :MOST_VALUES_THE_JSON_BYTES_HOLD

        def self.json_of(details)
          return nil unless details.is_a?(Hash)

          reported_form = new.reported_form_of(details)
          return nil if reported_form.nil? || reported_form.length > MOST_TOP_LEVEL_KEYS

          json_text = CompactJsonText.of(reported_form)
          WrittenJson.new(text: json_text) if json_text.bytesize <= MOST_JSON_BYTES
        end

        private_class_method :new

        def initialize
          @values_left = MOST_VALUES_THE_JSON_BYTES_HOLD
        end

        def reported_form_of(details)
          catch(:not_reportable) { form_of(details, 1) }
        end

        private

        def form_of(value, level)
          count_one_more_value
          return ReportedTime.of(value) if value.is_a?(Time)

          case value
          when String, Integer, Float, true, false, nil then value
          when Symbol then value.name
          when Array, Hash then container_form_of(value, level)
          else throw :not_reportable
          end
        end

        def count_one_more_value
          @values_left -= 1
          throw :not_reportable if @values_left.negative?
        end

        def container_form_of(container, level)
          throw :not_reportable if level > CompactJsonText::MOST_LEVELS_WRITTEN

          case container
          when Array then container.map { |element| form_of(element, level + 1) }
          else container.to_h { |key, member| [name_of(key), form_of(member, level + 1)] }
          end
        end

        def name_of(key)
          case key
          when String then key
          when Symbol then key.name
          else throw :not_reportable
          end
        end
      end
    end
  end
end
