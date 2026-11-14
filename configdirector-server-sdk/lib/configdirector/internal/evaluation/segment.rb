# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      Segment = Data.define(:condition_groups)

      class Segment
        def contains?(context)
          condition_groups.any? do |condition_group|
            condition_group.all? { |condition| condition.holds_for?(context, {}) }
          end
        end
      end
    end
  end
end
