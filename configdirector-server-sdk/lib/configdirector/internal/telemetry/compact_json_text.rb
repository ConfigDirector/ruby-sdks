# frozen_string_literal: true

require "json"

module ConfigDirector
  module Internal
    module Telemetry
      module CompactJsonText
        MOST_LEVELS_WRITTEN = 100

        private_constant :MOST_LEVELS_WRITTEN

        def self.of(value)
          text_inside(value, [])
        end

        def self.text_inside(value, containers_around_it)
          case value
          when nil then "null"
          when true, false then value.to_s
          when Integer, Float then number_text_of(value)
          when Array, Hash then container_text_inside(value, containers_around_it)
          else string_text_of(value.to_s)
          end
        end

        def self.number_text_of(number)
          number.abs <= Float::MAX ? Evaluation::ScalarText.of(number).to_s : "null"
        end

        def self.container_text_inside(container, containers_around_it)
          return "null" if containers_around_it.length >= MOST_LEVELS_WRITTEN
          return "null" if containers_around_it.any? { |container_around_it| container_around_it.equal?(container) }

          containers_around_its_contents = containers_around_it + [container]
          case container
          when Array then "[#{element_texts_of(container, containers_around_its_contents).join(",")}]"
          else "{#{member_texts_of(container, containers_around_its_contents).join(",")}}"
          end
        end

        def self.element_texts_of(array, containers_around_its_contents)
          array.dup.map { |element| text_inside(element, containers_around_its_contents) }
        end

        def self.member_texts_of(hash, containers_around_its_contents)
          hash.to_a.map do |key, member|
            "#{string_text_of(key.to_s)}:#{text_inside(member, containers_around_its_contents)}"
          end
        end

        def self.string_text_of(text)
          JSON.generate(ReportedText.of(text))
        end

        private_class_method :text_inside, :number_text_of, :container_text_inside, :element_texts_of, :member_texts_of,
                             :string_text_of
      end
    end
  end
end
