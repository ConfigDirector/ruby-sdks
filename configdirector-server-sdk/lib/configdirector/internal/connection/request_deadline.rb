# frozen_string_literal: true

require "timeout"

module ConfigDirector
  module Internal
    module Connection
      class RequestDeadline
        attr_reader :seconds_the_request_may_take

        def self.on_the_clock_of_the_process(seconds_the_request_may_take)
          new(
            seconds_the_request_may_take: seconds_the_request_may_take,
            monotonic_seconds: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
          )
        end

        def initialize(seconds_the_request_may_take:, monotonic_seconds:)
          @seconds_the_request_may_take = seconds_the_request_may_take
          @monotonic_seconds = monotonic_seconds
          @passes_at = monotonic_seconds.call + seconds_the_request_may_take
        end

        def description_of_having_passed
          "the SDK server gave no complete answer within #{format("%g", @seconds_the_request_may_take)} seconds"
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
