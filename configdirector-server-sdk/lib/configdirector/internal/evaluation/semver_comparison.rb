# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      module SemverComparison
        COERCIBLE_VERSION = /(?:\A|[^0-9])([0-9]{1,16})(?:\.([0-9]{1,16}))?(?:\.([0-9]{1,16}))?(?:\z|[^0-9])/

        NEVER_MATCHES = ->(_version, _targets) { false }

        OPERATORS = {
          "=" => ->(version, targets) { [0].include?(ordering(version, targets.first)) },
          "<" => ->(version, targets) { [-1].include?(ordering(version, targets.first)) },
          "<=" => ->(version, targets) { [-1, 0].include?(ordering(version, targets.first)) },
          ">" => ->(version, targets) { [1].include?(ordering(version, targets.first)) },
          ">=" => ->(version, targets) { [0, 1].include?(ordering(version, targets.first)) },
          "is one of" => ->(version, targets) { equals_any?(version, targets) },
          "is not one of" => ->(version, targets) { !equals_any?(version, targets) }
        }.freeze

        def self.matches?(text, operator, targets)
          OPERATORS.fetch(operator, NEVER_MATCHES).call(coerce(text), targets)
        end

        def self.coerce(text)
          match = COERCIBLE_VERSION.match(text)
          return nil if match.nil?

          major, minor, patch = match.captures
          [major.to_i, minor.to_i, patch.to_i]
        end

        def self.ordering(version, target_text)
          target = target_text.nil? ? nil : coerce(target_text)
          return nil if version.nil? || target.nil?

          version <=> target
        end

        def self.equals_any?(version, targets)
          targets.any? { |target| ordering(version, target)&.zero? }
        end

        private_constant :COERCIBLE_VERSION, :NEVER_MATCHES, :OPERATORS
        private_class_method :coerce, :ordering, :equals_any?
      end
    end
  end
end
