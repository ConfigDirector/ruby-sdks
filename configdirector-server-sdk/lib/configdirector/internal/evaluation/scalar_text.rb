# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      module ScalarText
        LAST_POINT_POSITION_SPELLED_OUT = 21
        FIRST_POINT_POSITION_SPELLED_OUT = -5

        def self.of(value)
          case value
          when String then value
          when true then "true"
          when false then "false"
          when Integer then value.to_s
          when Float then of_float(value)
          end
        end

        def self.of_float(number)
          if number.nan? then "NaN"
          elsif number.infinite? then number.positive? ? "Infinity" : "-Infinity"
          elsif number.zero? then "0"
          elsif number.negative? then "-#{of_positive_float(-number)}"
          else of_positive_float(number)
          end
        end

        def self.of_positive_float(number)
          digits, point_position = shortest_digits_and_point_position(number)

          if point_position.between?(digits.length, LAST_POINT_POSITION_SPELLED_OUT)
            digits + ("0" * (point_position - digits.length))
          elsif point_position.between?(1, LAST_POINT_POSITION_SPELLED_OUT)
            "#{digits[0, point_position]}.#{digits[point_position..]}"
          elsif point_position.between?(FIRST_POINT_POSITION_SPELLED_OUT, 0)
            "0.#{"0" * -point_position}#{digits}"
          else
            exponent_form(digits, point_position - 1)
          end
        end

        def self.shortest_digits_and_point_position(number)
          mantissa, exponent = number.to_s.split("e")
          whole, fraction = mantissa.to_s.split(".")
          digits = "#{whole}#{fraction}"
          significant_digits = digits.sub(/\A0+/, "")
          leading_zero_count = digits.length - significant_digits.length

          [significant_digits.sub(/0+\z/, ""), whole.to_s.length + exponent.to_i - leading_zero_count]
        end

        def self.exponent_form(digits, exponent)
          mantissa = digits.length == 1 ? digits : "#{digits[0]}.#{digits[1..]}"

          "#{mantissa}e#{exponent.negative? ? "-" : "+"}#{exponent.abs}"
        end

        private_constant :LAST_POINT_POSITION_SPELLED_OUT, :FIRST_POINT_POSITION_SPELLED_OUT
        private_class_method :of_float, :of_positive_float, :shortest_digits_and_point_position, :exponent_form
      end
    end
  end
end
