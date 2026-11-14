# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      module ContextKind
        VALID_KIND = /\A[a-z0-9_-]{1,64}\z/
        SAMPLE_MAXIMUM_CHARACTERS = 128

        def self.valid?(kind)
          kind.is_a?(String) && kind.b.match?(VALID_KIND)
        end

        def self.sample_of(kind)
          kind.to_s[0, SAMPLE_MAXIMUM_CHARACTERS].to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).scrub
        rescue StandardError
          kind.class.to_s
        end

        private_constant :VALID_KIND, :SAMPLE_MAXIMUM_CHARACTERS
      end
    end
  end
end
