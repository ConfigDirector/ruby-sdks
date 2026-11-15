# frozen_string_literal: true

require "timeout"

module ConfigDirector
  module Internal
    module Polling
      class PollDeadline
        attr_reader :seconds_a_poll_may_take

        def initialize(timing)
          @seconds_a_poll_may_take = timing.seconds_a_poll_may_take
          @monotonic_seconds = timing.monotonic_seconds
          @passes_at = @monotonic_seconds.call + timing.seconds_a_poll_may_take
        end

        def seconds_left
          seconds_left = @passes_at - @monotonic_seconds.call
          raise Timeout::Error unless seconds_left.positive?

          seconds_left
        end
      end
    end
  end
end
