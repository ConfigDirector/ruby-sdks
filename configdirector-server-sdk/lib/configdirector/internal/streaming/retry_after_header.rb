# frozen_string_literal: true

require "time"

module ConfigDirector
  module Internal
    module Streaming
      module RetryAfterHeader
        ASCII_DIGITS = /\A[0-9]+\z/

        private_constant :ASCII_DIGITS

        def self.seconds_to_wait(header_value, now)
          return nil if header_value.nil?
          return Integer(header_value, 10) if header_value.match?(ASCII_DIGITS)

          [Time.httpdate(header_value) - now, 0].max
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
