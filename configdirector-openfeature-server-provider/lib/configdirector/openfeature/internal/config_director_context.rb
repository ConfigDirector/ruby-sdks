# frozen_string_literal: true

module ConfigDirector
  module OpenFeature
    module Internal
      module ConfigDirectorContext
        MOST_LEVELS_OF_TRAITS = 100

        private_constant :MOST_LEVELS_OF_TRAITS

        def self.of(evaluation_context)
          return nil if evaluation_context.nil?

          fields = evaluation_context.fields
          ConfigDirector::Context.new(
            id: text_of(evaluation_context.targeting_key.nil? ? fields["id"] : evaluation_context.targeting_key),
            kind: fields["kind"], name: text_of(fields["name"]), traits: traits_of(fields["traits"]),
            anonymous: fields["anonymous"] == true
          )
        end

        def self.text_of(value)
          case value
          when String then value
          when Symbol then value.name
          when true, false, Integer, Float then value.to_s
          else DateText.of(value)
          end
        end

        def self.traits_of(traits)
          return nil unless traits.is_a?(Hash) && !traits.empty?

          with_dates_as_text(traits, 1)
        end

        def self.with_dates_as_text(trait, level)
          date_text = DateText.of(trait)
          return date_text unless date_text.nil?
          return trait if level > MOST_LEVELS_OF_TRAITS

          case trait
          when Hash then trait.transform_values { |member| with_dates_as_text(member, level + 1) }
          when Array then trait.map { |element| with_dates_as_text(element, level + 1) }
          else trait
          end
        end

        private_class_method :text_of, :traits_of, :with_dates_as_text
      end
    end
  end
end
