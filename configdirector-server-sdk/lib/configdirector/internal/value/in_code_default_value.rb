# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Value
      InCodeDefaultValue = Data.define(:value, :kind)

      class InCodeDefaultValue
        def self.from(default_value)
          kind = kind_of(default_value) || raise(
            ConfigDirectorValidationError,
            "Invalid in-code default value of class #{default_value.class}. The in-code default value " \
            "for a config must be true, false, a String, an Integer, a Float, a Hash or an Array."
          )
          new(value: default_value, kind: kind)
        end

        def self.kind_of(default_value)
          case default_value
          when true, false then :boolean
          when String then :string
          when Integer then :integer
          when Float then :float
          when Hash then :json_object
          when Array then :json_array
          end
        end

        private_class_method :kind_of
      end
    end
  end
end
