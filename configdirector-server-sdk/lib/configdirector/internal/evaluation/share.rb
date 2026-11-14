# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      Share = Data.define(:id, :percentage, :value, :value_id, :variation_id)
    end
  end
end
