# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Value
      module PlainDecimalText
        DIGITS_UP_TO_THE_LAST_NONZERO_ONE = /\A[0-9]*[1-9]/

        private_constant :DIGITS_UP_TO_THE_LAST_NONZERO_ONE

        def self.of(finite_float)
          mantissa, exponent = finite_float.to_s.split("e")
          sign = finite_float.to_s.start_with?("-") ? "-" : ""
          whole_digits, fraction_digits = mantissa.to_s.delete_prefix("-").split(".")
          integer_part, fraction_part = parts_around_the_point(
            "#{whole_digits}#{fraction_digits}", whole_digits.to_s.length + exponent.to_i
          )
          significant_fraction = fraction_part[DIGITS_UP_TO_THE_LAST_NONZERO_ONE]

          significant_fraction.nil? ? "#{sign}#{integer_part}" : "#{sign}#{integer_part}.#{significant_fraction}"
        end

        def self.parts_around_the_point(digits, digits_before_the_point)
          return ["0", "#{"0" * -digits_before_the_point}#{digits}"] unless digits_before_the_point.positive?

          [
            digits[0, digits_before_the_point].to_s.ljust(digits_before_the_point, "0"),
            digits[digits_before_the_point..].to_s
          ]
        end

        private_class_method :parts_around_the_point
      end
    end
  end
end
