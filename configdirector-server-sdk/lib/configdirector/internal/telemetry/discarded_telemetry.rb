# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      class DiscardedTelemetry
        def self.for_a_client_with(**)
          new
        end

        def record_evaluation(_evaluated_read); end

        def record_tracked_event(_admission)
          []
        end

        def count_invalid_context(_kind_sample)
          :new_kind_sample
        end

        def start_reporting; end

        def choose_the_reporter_of_what_the_parent_process_collected(_forked_through); end

        def restart_in_a_forked_process; end

        def close; end
      end
    end
  end
end
