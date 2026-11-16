# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      class DiscardedTelemetry
        def self.for_a_client_with(**)
          new
        end

        def record(_evaluated_read)
          nil
        end

        def count_invalid_context(_kind_sample)
          :new_kind_sample
        end

        def start_reporting
          nil
        end

        def restart_in_a_forked_process(_forked_through)
          nil
        end

        def close
          nil
        end
      end
    end
  end
end
