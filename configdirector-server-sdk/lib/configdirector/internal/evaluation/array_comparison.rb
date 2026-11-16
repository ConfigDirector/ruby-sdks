# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      module ArrayComparison
        def self.matches?(value, operator, targets)
          contains_any_target = value.is_a?(Array) && contains_any?(value, targets)

          case operator
          when "contains any of" then contains_any_target
          when "does not contain any of" then !contains_any_target
          else false
          end
        end

        def self.contains_any?(elements, targets)
          elements.filter_map { |element| ScalarText.of(element) }.intersect?(targets)
        end

        private_class_method :contains_any?
      end
    end
  end
end
