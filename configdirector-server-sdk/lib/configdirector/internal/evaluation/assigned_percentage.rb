# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      module AssignedPercentage
        SEED = 0x397832987
        REACHABLE_TENTHS_OF_A_PERCENT = 1000

        def self.of(config_id, identifier, context_kind)
          hash_input = "#{identifier}-#{config_id}"
          hash_input = "#{hash_input}:#{context_kind}" unless context_kind == EvaluationContext::USER_CONTEXT_KIND

          (Rapidhash.of(hash_input, SEED) % REACHABLE_TENTHS_OF_A_PERCENT) / 10.0
        end

        private_constant :SEED, :REACHABLE_TENTHS_OF_A_PERCENT
      end
    end
  end
end
