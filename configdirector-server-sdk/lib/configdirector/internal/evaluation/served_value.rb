# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      ServedValue = Data.define(:value, :value_id, :variation_id, :rollout_share, :served_by)
    end
  end
end
