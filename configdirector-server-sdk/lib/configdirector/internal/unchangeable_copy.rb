# frozen_string_literal: true

module ConfigDirector
  module Internal
    module UnchangeableCopy
      def self.of(value)
        case value
        when Hash then value.to_h { |key, member| [of(key), of(member)] }.freeze
        when Array then value.map { |element| of(element) }.freeze
        when String then value.frozen? ? value : value.dup.freeze
        else value
        end
      end
    end
  end
end
