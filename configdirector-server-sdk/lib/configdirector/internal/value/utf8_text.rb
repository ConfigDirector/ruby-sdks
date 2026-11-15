# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Value
      module Utf8Text
        def self.of(text)
          utf8_text = case text.encoding
                      when Encoding::BINARY then String.new(text, encoding: Encoding::UTF_8)
                      else text.encode(Encoding::UTF_8)
                      end
          utf8_text.valid_encoding? ? utf8_text.freeze : nil
        rescue EncodingError
          nil
        end
      end
    end
  end
end
