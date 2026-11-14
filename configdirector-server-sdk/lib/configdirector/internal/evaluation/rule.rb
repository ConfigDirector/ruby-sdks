# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      Rule = Data.define(:id, :order, :type, :target, :value, :value_id, :variation_id, :conditions, :shares)

      class Rule
        def serve(config_id, context, segments)
          case type
          when "conditional" then serve_when_every_condition_holds(config_id, context, segments)
          when "percentage" then serve_from_rollout(config_id, context)
          else :not_matched
          end
        end

        private

        def serve_when_every_condition_holds(config_id, context, segments)
          return :not_matched unless conditions.all? { |condition| condition.holds_for?(context, segments) }

          case target
          when "value" then serve_value
          when "percentage" then serve_from_rollout(config_id, context)
          else :not_matched
          end
        end

        def serve_value
          return :not_matched if value.nil?

          ServedValue.new(
            value: value, value_id: value_id, variation_id: variation_id, rollout_share: nil, served_by: :matching_rule
          )
        end

        def serve_from_rollout(config_id, context)
          rollout_shares = shares
          return :not_matched if rollout_shares.nil?

          identifier = context.identifier
          return :rollout_skipped_no_identifier if identifier.nil?

          share = share_covering(rollout_shares, AssignedPercentage.of(config_id, identifier, context.effective_kind))
          share_value = share&.value
          share.nil? || share_value.nil? ? :not_matched : serve_share(share, share_value)
        end

        def share_covering(rollout_shares, assigned_percentage)
          share_end = 0.0
          rollout_shares.find do |share|
            share_end += share.percentage
            assigned_percentage < share_end
          end
        end

        def serve_share(share, share_value)
          ServedValue.new(
            value: share_value, value_id: share.value_id, variation_id: share.variation_id,
            rollout_share: RolloutShare.new(rule_id: id, share_id: share.id), served_by: :matching_rule
          )
        end
      end
    end
  end
end
