# frozen_string_literal: true

require "json"

module ConfigDirector
  module Internal
    module Connection
      module ServerSdkPayloadParser
        DELTA_KIND = "delta"

        private_constant :DELTA_KIND

        def self.payload_in(payload_text)
          wire_payload = JSON.parse(payload_text, allow_duplicate_key: true)
          raise NotAServerSdkPayload, "it is not a JSON object" unless wire_payload.is_a?(Hash)

          wire_configs = wire_payload["configs"]
          raise NotAServerSdkPayload, "it carries no configs object" unless wire_configs.is_a?(Hash)

          wire_segments = wire_payload["segments"]
          payload_defined_by(wire_payload["kind"], wire_configs, wire_segments.is_a?(Hash) ? wire_segments : {})
        end

        def self.payload_defined_by(wire_kind, wire_configs, wire_segments)
          configs, unreadable_configs = definitions_read_in(wire_configs) do |wire_config|
            config_defined_by(wire_config)
          end
          segments, unreadable_segments = definitions_read_in(wire_segments) do |wire_segment|
            segment_defined_by(wire_segment)
          end

          ServerSdkPayload.new(
            delta: wire_kind == DELTA_KIND, configs: configs, segments: segments,
            unreadable_configs: unreadable_configs, unreadable_segments: unreadable_segments
          )
        end

        def self.definitions_read_in(wire_definitions)
          definitions_or_failures = wire_definitions.map do |config_key_or_segment_id, wire_definition|
            [config_key_or_segment_id, yield(wire_definition)]
          rescue UnreadableDefinition => e
            [config_key_or_segment_id, e]
          end
          failures, definitions = definitions_or_failures.partition do |_, definition_or_failure|
            definition_or_failure.is_a?(UnreadableDefinition)
          end

          [definitions.to_h, failures.to_h.transform_values(&:message)]
        end

        def self.config_defined_by(wire_config)
          wire_target = WireFields.object_or_nil_in(wire_config, "target")
          raise UnreadableDefinition, "the config has no target" if wire_target.nil?

          ConfigDefinition.new(
            id: WireFields.text_required_in(wire_config, "id", "the config"),
            key: WireFields.text_required_in(wire_config, "key", "the config"),
            type: WireFields.text_required_in(wire_config, "type", "the config"),
            targeting_rules: TargetingRulesParser.targeting_rules_defined_by(wire_target),
            variations: variations_listed_in(wire_config)
          )
        end

        def self.variations_listed_in(wire_config)
          WireFields.list_in(wire_config, "variations", "the config").filter_map do |wire_variation|
            variation_id = wire_variation.is_a?(Hash) ? WireFields.text_or_nil_in(wire_variation, "id") : nil
            next if variation_id.nil?

            Variation.new(id: variation_id, name: WireFields.text_or_nil_in(wire_variation, "name"))
          end
        end

        def self.segment_defined_by(wire_segment)
          wire_condition_groups = WireFields.list_or_nil_in(wire_segment, "groups")
          raise UnreadableDefinition, "the segment has no groups" if wire_condition_groups.nil?

          Evaluation::Segment.new(
            condition_groups: wire_condition_groups.map do |wire_condition_group|
              ConditionParser.condition_group_defined_by(wire_condition_group)
            end
          )
        end

        private_class_method :payload_defined_by, :definitions_read_in, :config_defined_by, :variations_listed_in,
                             :segment_defined_by
      end
    end
  end
end
