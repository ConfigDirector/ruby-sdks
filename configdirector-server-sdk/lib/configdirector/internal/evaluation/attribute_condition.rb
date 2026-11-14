# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      AttributeCondition = Data.define(:attribute, :trait, :operator, :target_type, :target_values)

      class AttributeCondition
        def holds_for?(context, _segments)
          case attribute
          when "identifier" then value_matches?(context.identifier)
          when "kind" then value_matches?(context.effective_kind)
          when "name" then value_matches?(context.name)
          when "appName" then value_matches?(context.app_name)
          when "appVersion" then value_matches?(context.app_version)
          when "traits" then value_matches?(trait_of(context))
          else false
          end
        end

        private

        def trait_of(context)
          pointer = trait
          pointer.nil? ? nil : TraitPointer.value_at(pointer, context.traits)
        end

        def value_matches?(value)
          lowercase_operator = operator.downcase
          text = ScalarText.of(value) || ""

          case target_type
          when "text" then TextComparison.matches?(text, lowercase_operator, target_values)
          when "number" then NumberComparison.matches?(value, lowercase_operator, target_values)
          when "semver" then SemverComparison.matches?(text, lowercase_operator, target_values)
          when "datetime" then DatetimeComparison.matches?(text, lowercase_operator, target_values)
          when "array" then ArrayComparison.matches?(value, lowercase_operator, target_values)
          else false
          end
        end
      end
    end
  end
end
