# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      EvaluatedRead = Data.define(:config_read, :evaluation, :config_state)
    end
  end
end
