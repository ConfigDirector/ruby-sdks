# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      module TraitPointer
        INVALID_ESCAPE = /~(?:[^01]|\z)/
        ESCAPE = /~[01]/
        DECODED_ESCAPES = { "~1" => "/", "~0" => "~" }.freeze
        ARRAY_INDEX = /\A(?:0|[1-9][0-9]*)\z/

        def self.value_at(pointer, traits)
          return nil unless pointer.start_with?("/")

          encoded_tokens = pointer.split("/", -1).drop(1)
          return nil if encoded_tokens.any? { |encoded_token| encoded_token.match?(INVALID_ESCAPE) }

          encoded_tokens.reduce(traits) do |container, encoded_token|
            member_of(container, encoded_token.gsub(ESCAPE, DECODED_ESCAPES))
          end
        end

        def self.member_of(container, token)
          case container
          when Hash then container.fetch(token, nil)
          when Array then element_of(container, token)
          end
        end

        def self.element_of(elements, token)
          return nil unless token.match?(ARRAY_INDEX)

          index = Integer(token, 10)
          index < elements.length ? elements[index] : nil
        end

        private_constant :INVALID_ESCAPE, :ESCAPE, :DECODED_ESCAPES, :ARRAY_INDEX
        private_class_method :member_of, :element_of
      end
    end
  end
end
