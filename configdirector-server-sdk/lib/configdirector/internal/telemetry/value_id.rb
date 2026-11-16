# frozen_string_literal: true

require "digest"

module ConfigDirector
  module Internal
    module Telemetry
      module ValueId
        DIGEST_BYTES = 16
        BASE62_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        LENGTH = 22

        private_constant :DIGEST_BYTES, :BASE62_DIGITS, :LENGTH

        def self.of(text)
          number = Digest::SHA256.digest(text).byteslice(0, DIGEST_BYTES).to_s.unpack1("H*").to_s.to_i(16)

          number.digits(BASE62_DIGITS.length).reverse.map { |digit| BASE62_DIGITS[digit] }.join.rjust(LENGTH, "0")
        end
      end
    end
  end
end
