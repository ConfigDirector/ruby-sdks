# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      module WireFields
        def self.object_or_nil_in(wire_object, field)
          object = wire_object.is_a?(Hash) ? wire_object[field] : nil

          object.is_a?(Hash) ? object : nil
        end

        def self.list_or_nil_in(wire_object, field)
          list = wire_object.is_a?(Hash) ? wire_object[field] : nil

          list.is_a?(Array) ? list : nil
        end

        def self.list_in(wire_object, field, owner)
          list = wire_object[field]
          return [] if list.nil?
          raise UnreadableDefinition, "#{owner} has '#{field}' that is not a list" unless list.is_a?(Array)

          list
        end

        def self.objects_listed_in(wire_object, field, owner, listed)
          list = list_in(wire_object, field, owner)
          raise UnreadableDefinition, "#{listed} is not an object" unless list.all?(Hash)

          list
        end

        def self.text_required_in(wire_object, field, owner)
          text = wire_object[field]
          raise UnreadableDefinition, "#{owner} has no #{field}" unless text.is_a?(String) && !text.empty?

          text
        end

        def self.text_or_nil_in(wire_object, field)
          text = wire_object[field]

          text.is_a?(String) ? text : nil
        end

        def self.text_or_empty_in(wire_object, field)
          text_or_nil_in(wire_object, field) || ""
        end

        def self.whole_number_or_nil_in(wire_object, field)
          whole_number = wire_object[field]

          whole_number.is_a?(Integer) ? whole_number : nil
        end
      end
    end
  end
end
