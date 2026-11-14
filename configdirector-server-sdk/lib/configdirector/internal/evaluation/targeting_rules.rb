# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      TargetingRules = Data.define(:default_value, :default_value_id, :default_variation_id, :rules)
    end
  end
end
