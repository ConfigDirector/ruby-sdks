# frozen_string_literal: true

require "json"

module ConfigDirector
  module Internal
    module Value
      module ParsedJson
        MOST_DIGITS_OF_A_NUMBER = 16_384
        MORE_DIGITS_THAN_A_NUMBER_HAS = ("0" * (MOST_DIGITS_OF_A_NUMBER + 1)).freeze
        QUOTE = '"'
        QUOTE_OR_SLASH = %r{["/]}
        QUOTE_OR_BACKSLASH = /["\\]/
        END_OF_A_COMMENT_BY_ITS_START = { "/*" => "*/", "//" => "\n" }.freeze

        def self.of(json_text)
          if number_with_too_many_digits_in?(json_text.b)
            raise JSON::ParserError, "it holds a number of more than 16,384 digits"
          end

          parsed_without_repeating_the_text_in_an_error(json_text)
        end

        def self.parsed_without_repeating_the_text_in_an_error(json_text)
          JSON.parse(json_text, allow_duplicate_key: true)
        rescue JSON::ParserError
          raise JSON::ParserError, "it is not valid JSON"
        end

        def self.number_with_too_many_digits_in?(json_bytes)
          run_of_too_many_digits_in?(json_bytes) &&
            run_of_too_many_digits_in?(bytes_outside_the_strings_and_comments_of(json_bytes))
        end

        def self.run_of_too_many_digits_in?(bytes)
          bytes.tr("0-9", "0").include?(MORE_DIGITS_THAN_A_NUMBER_HAS)
        end

        def self.bytes_outside_the_strings_and_comments_of(json_bytes)
          bytes_outside = String.new(encoding: Encoding::BINARY)
          position = 0
          while (quote_or_slash = json_bytes.byteindex(QUOTE_OR_SLASH, position))
            bytes_outside << json_bytes.byteslice(position, quote_or_slash - position).to_s
            position = position_after_what_opens_at(quote_or_slash, json_bytes)
          end

          bytes_outside << json_bytes.byteslice(position..).to_s
        end

        def self.position_after_what_opens_at(quote_or_slash, json_bytes)
          return position_after_the_string_opened_at(quote_or_slash, json_bytes) if json_bytes[quote_or_slash] == QUOTE

          end_of_the_comment = END_OF_A_COMMENT_BY_ITS_START[json_bytes.byteslice(quote_or_slash, 2)]
          return quote_or_slash + 1 if end_of_the_comment.nil?

          comment_end = json_bytes.byteindex(end_of_the_comment, quote_or_slash + 2)
          comment_end.nil? ? json_bytes.bytesize : comment_end + end_of_the_comment.bytesize
        end

        def self.position_after_the_string_opened_at(opening_quote, json_bytes)
          position = opening_quote + 1
          while (quote_or_backslash = json_bytes.byteindex(QUOTE_OR_BACKSLASH, position))
            return quote_or_backslash + 1 if json_bytes[quote_or_backslash] == QUOTE

            position = quote_or_backslash + 2
          end

          json_bytes.bytesize
        end

        private_constant :MORE_DIGITS_THAN_A_NUMBER_HAS, :QUOTE, :QUOTE_OR_SLASH, :QUOTE_OR_BACKSLASH,
                         :END_OF_A_COMMENT_BY_ITS_START
        private_class_method :parsed_without_repeating_the_text_in_an_error, :number_with_too_many_digits_in?,
                             :run_of_too_many_digits_in?, :bytes_outside_the_strings_and_comments_of,
                             :position_after_what_opens_at, :position_after_the_string_opened_at
      end
    end
  end
end
