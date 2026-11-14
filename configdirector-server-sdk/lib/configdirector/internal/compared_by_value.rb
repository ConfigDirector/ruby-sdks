# frozen_string_literal: true

module ConfigDirector
  module Internal
    module ComparedByValue
      def ==(other)
        other.instance_of?(self.class) && other.attribute_values == attribute_values
      end

      def eql?(other)
        other.instance_of?(self.class) && other.attribute_values.eql?(attribute_values)
      end

      def hash
        [self.class, attribute_values].hash
      end

      protected

      def attribute_values
        instance_variables.map { |name| instance_variable_get(name) }
      end
    end
  end
end
