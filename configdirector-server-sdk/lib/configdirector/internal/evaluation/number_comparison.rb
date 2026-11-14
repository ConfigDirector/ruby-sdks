# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      module NumberComparison
        NumberOperator = Data.define(:holds, :holds_for_an_unparseable_value)

        EQUALS = NumberOperator.new(
          holds: ->(number, target) { number == target }, holds_for_an_unparseable_value: false
        )
        DOES_NOT_EQUAL = NumberOperator.new(
          holds: ->(number, target) { number != target }, holds_for_an_unparseable_value: true
        )

        OPERATORS = {
          "=" => EQUALS,
          "equals" => EQUALS,
          "!=" => DOES_NOT_EQUAL,
          "does not equal" => DOES_NOT_EQUAL,
          "<" => NumberOperator.new(
            holds: ->(number, target) { number < target }, holds_for_an_unparseable_value: false
          ),
          "<=" => NumberOperator.new(
            holds: ->(number, target) { number <= target }, holds_for_an_unparseable_value: false
          ),
          ">" => NumberOperator.new(
            holds: ->(number, target) { number > target }, holds_for_an_unparseable_value: false
          ),
          ">=" => NumberOperator.new(
            holds: ->(number, target) { number >= target }, holds_for_an_unparseable_value: false
          )
        }.freeze

        DECIMAL_LITERAL = /
          \A(?<sign>[+-]?)(?<whole>[0-9]*)(?:\.(?<fraction>[0-9]*))?(?:[eE](?<exponent>[+-]?[0-9]+))?\z
        /x

        ROUNDS_TO_INFINITY_FROM = (1 << 1024) - (1 << 970)
        ROUNDS_TO_ZERO_UP_TO = Rational(1, 1 << 1075)
        LARGEST_FLOAT_DECIMAL_EXPONENT = 308
        SMALLEST_FLOAT_DECIMAL_EXPONENT = -324

        def self.matches?(value, operator, targets)
          number_operator = OPERATORS[operator]
          return false if number_operator.nil?

          number = finite_number_of(value)
          return number_operator.holds_for_an_unparseable_value if number.nil?

          target = targets.empty? ? nil : finite_number_in(targets.first)
          return false if target.nil?

          number_operator.holds.call(number, target)
        end

        def self.finite_number_of(value)
          case value
          when Integer then value.abs < ROUNDS_TO_INFINITY_FROM ? value.to_f : nil
          when Float then value.finite? ? value : nil
          when String then finite_number_in(value)
          end
        end

        def self.finite_number_in(text)
          decimal_parts = decimal_parts_of(text)
          return nil if decimal_parts.nil?

          sign, significant_digits, power_of_ten = decimal_parts
          return 0.0 if significant_digits.empty?

          case rounding_of(significant_digits, power_of_ten)
          when :overflows then nil
          when :underflows then 0.0
          when :fits then Float("#{sign}#{significant_digits}e#{power_of_ten}")
          end
        end

        def self.decimal_parts_of(text)
          literal = DECIMAL_LITERAL.match(text)
          return nil if literal.nil?

          digits = "#{literal[:whole]}#{literal[:fraction]}"
          return nil if digits.empty?

          [literal[:sign].to_s, digits.sub(/\A0+/, ""), literal[:exponent].to_i - literal[:fraction].to_s.length]
        end

        def self.rounding_of(significant_digits, power_of_ten)
          case significant_digits.length - 1 + power_of_ten
          when ((LARGEST_FLOAT_DECIMAL_EXPONENT + 1)..) then :overflows
          when LARGEST_FLOAT_DECIMAL_EXPONENT then rounding_near_the_largest_float(significant_digits, power_of_ten)
          when (...SMALLEST_FLOAT_DECIMAL_EXPONENT) then :underflows
          when SMALLEST_FLOAT_DECIMAL_EXPONENT then rounding_near_the_smallest_float(significant_digits, power_of_ten)
          else :fits
          end
        end

        def self.rounding_near_the_largest_float(significant_digits, power_of_ten)
          exact_value(significant_digits, power_of_ten) >= ROUNDS_TO_INFINITY_FROM ? :overflows : :fits
        end

        def self.rounding_near_the_smallest_float(significant_digits, power_of_ten)
          exact_value(significant_digits, power_of_ten) <= ROUNDS_TO_ZERO_UP_TO ? :underflows : :fits
        end

        def self.exact_value(significant_digits, power_of_ten)
          Rational(Integer(significant_digits, 10)) * (Rational(10)**power_of_ten)
        end

        private_constant :NumberOperator, :EQUALS, :DOES_NOT_EQUAL, :OPERATORS, :DECIMAL_LITERAL,
                         :ROUNDS_TO_INFINITY_FROM, :ROUNDS_TO_ZERO_UP_TO, :LARGEST_FLOAT_DECIMAL_EXPONENT,
                         :SMALLEST_FLOAT_DECIMAL_EXPONENT
        private_class_method :finite_number_of, :finite_number_in, :decimal_parts_of, :rounding_of,
                             :rounding_near_the_largest_float, :rounding_near_the_smallest_float, :exact_value
      end
    end
  end
end
