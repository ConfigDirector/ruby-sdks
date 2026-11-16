# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      module TextComparison
        EQUALS_THE_FIRST_TARGET = ->(text, targets) { !targets.empty? && text == targets.first }.freeze
        DIFFERS_FROM_THE_FIRST_TARGET = ->(text, targets) { !targets.empty? && text != targets.first }.freeze
        NEVER_MATCHES = ->(_text, _targets) { false }.freeze

        OPERATORS = {
          "=" => EQUALS_THE_FIRST_TARGET,
          "equals" => EQUALS_THE_FIRST_TARGET,
          "!=" => DIFFERS_FROM_THE_FIRST_TARGET,
          "does not equal" => DIFFERS_FROM_THE_FIRST_TARGET,
          "is one of" => ->(text, targets) { targets.include?(text) },
          "is not one of" => ->(text, targets) { !targets.include?(text) },
          "starts with any of" => ->(text, targets) { text.start_with?(*targets) },
          "does not start with any of" => ->(text, targets) { !text.start_with?(*targets) },
          "ends with any of" => ->(text, targets) { text.end_with?(*targets) },
          "does not end with any of" => ->(text, targets) { !text.end_with?(*targets) }
        }.freeze

        private_constant :EQUALS_THE_FIRST_TARGET, :DIFFERS_FROM_THE_FIRST_TARGET, :NEVER_MATCHES, :OPERATORS

        def self.matches?(text, operator, targets)
          OPERATORS.fetch(operator, NEVER_MATCHES).call(text, targets)
        end
      end
    end
  end
end
