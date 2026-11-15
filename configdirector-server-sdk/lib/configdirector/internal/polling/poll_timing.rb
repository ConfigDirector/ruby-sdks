# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Polling
      PollTiming = Data.define(
        :seconds_between_polls,
        :seconds_a_poll_may_take,
        :pause_before_the_next_poll,
        :monotonic_seconds
      )

      class PollTiming
        def self.on_the_clock_of_the_process(seconds_between_polls:, seconds_a_poll_may_take:)
          new(
            seconds_between_polls: seconds_between_polls,
            seconds_a_poll_may_take: seconds_a_poll_may_take,
            pause_before_the_next_poll: ->(seconds) { sleep(seconds) },
            monotonic_seconds: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
          )
        end
      end
    end
  end
end
