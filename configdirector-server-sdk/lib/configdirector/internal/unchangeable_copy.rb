# frozen_string_literal: true

module ConfigDirector
  module Internal
    module UnchangeableCopy
      MOST_LEVELS_THE_SDK_READS_OF_A_VALUE = 101

      private_constant :MOST_LEVELS_THE_SDK_READS_OF_A_VALUE

      def self.of(value)
        nested_deeper_than?(MOST_LEVELS_THE_SDK_READS_OF_A_VALUE, value) ? value : copy_of(value)
      end

      def self.nested_deeper_than?(levels, value)
        case value
        when Hash then any_nested_deeper_than?(levels, value.keys + value.values)
        when Array then any_nested_deeper_than?(levels, value)
        else false
        end
      end

      def self.any_nested_deeper_than?(levels, contents)
        levels.zero? || contents.any? { |key_member_or_element| nested_deeper_than?(levels - 1, key_member_or_element) }
      end

      def self.copy_of(value)
        case value
        when Hash then value.to_h { |key, member| [copy_of(key), copy_of(member)] }.freeze
        when Array then value.map { |element| copy_of(element) }.freeze
        when String then value.frozen? ? value : value.dup.freeze
        else value
        end
      end

      private_class_method :nested_deeper_than?, :any_nested_deeper_than?, :copy_of
    end
  end
end
