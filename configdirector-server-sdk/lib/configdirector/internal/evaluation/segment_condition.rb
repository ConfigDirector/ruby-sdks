# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      SegmentCondition = Data.define(:operator, :segment_id)

      class SegmentCondition
        def holds_for?(context, segments)
          segment = segments[segment_id]
          return false if segment.nil?

          case operator.downcase
          when "in" then segment.contains?(context)
          when "not in" then !segment.contains?(context)
          else false
          end
        end

        def uses_any_segment_of?(segment_ids)
          segment_ids.include?(segment_id)
        end
      end
    end
  end
end
