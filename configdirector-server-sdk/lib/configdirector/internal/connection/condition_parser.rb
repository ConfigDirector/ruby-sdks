# frozen_string_literal: true

require "json"

module ConfigDirector
  module Internal
    module Connection
      module ConditionParser
        ATTRIBUTE_KIND = "attribute"
        SEGMENT_KIND = "segment"

        private_constant :ATTRIBUTE_KIND, :SEGMENT_KIND

        def self.condition_defined_by(wire_condition)
          kind = kind_named_in(wire_condition)
          case kind
          when ATTRIBUTE_KIND then attribute_condition_defined_by(wire_condition)
          when SEGMENT_KIND then segment_condition_defined_by(wire_condition)
          else
            raise UnreadableDefinition,
                  "a condition has the unknown kind '#{Evaluation::ScalarText.of(kind) || JSON.generate(kind)}'"
          end
        end

        def self.condition_group_defined_by(wire_condition_group)
          unless wire_condition_group.is_a?(Array)
            raise UnreadableDefinition, "a condition group of the segment is not a list"
          end

          wire_condition_group.map do |wire_condition|
            unless wire_condition.is_a?(Hash) && kind_named_in(wire_condition) == ATTRIBUTE_KIND
              raise UnreadableDefinition, "a condition group of the segment holds attribute conditions only"
            end

            attribute_condition_defined_by(wire_condition)
          end
        end

        def self.kind_named_in(wire_condition)
          kind = wire_condition["kind"]

          kind.nil? ? ATTRIBUTE_KIND : kind
        end

        def self.attribute_condition_defined_by(wire_condition)
          Evaluation::AttributeCondition.new(
            attribute: WireFields.text_required_in(wire_condition, "attribute", "a condition"),
            trait: WireFields.text_or_nil_in(wire_condition, "trait"),
            operator: WireFields.text_required_in(wire_condition, "operator", "a condition"),
            target_type: WireFields.text_required_in(wire_condition, "targetType", "a condition"),
            target_values: WireFields.list_in(wire_condition, "targetValues", "a condition").map do |wire_target_value|
              target_value_text_of(wire_target_value)
            end
          )
        end

        def self.target_value_text_of(wire_target_value)
          Evaluation::ScalarText.of(wire_target_value) ||
            raise(UnreadableDefinition, "a condition has a target value that is not text")
        end

        def self.segment_condition_defined_by(wire_condition)
          Evaluation::SegmentCondition.new(
            operator: WireFields.text_required_in(wire_condition, "operator", "a segment condition"),
            segment_id: WireFields.text_required_in(wire_condition, "segmentId", "a segment condition")
          )
        end

        private_class_method :kind_named_in, :attribute_condition_defined_by, :target_value_text_of,
                             :segment_condition_defined_by
      end
    end
  end
end
