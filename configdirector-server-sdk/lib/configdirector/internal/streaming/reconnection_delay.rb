# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Streaming
      module ReconnectionDelay
        MAXIMUM_BACKOFF_EXPONENT = 9
        SHORTEST_WAIT_THE_SERVER_CAN_ASK_FOR_SECONDS = 1
        LONGEST_WAIT_THE_SERVER_CAN_ASK_FOR_SECONDS = 3600

        private_constant :MAXIMUM_BACKOFF_EXPONENT, :SHORTEST_WAIT_THE_SERVER_CAN_ASK_FOR_SECONDS,
                         :LONGEST_WAIT_THE_SERVER_CAN_ASK_FOR_SECONDS

        def self.seconds_before_attempt(attempt, seconds_the_server_asked_to_wait:, random_fraction:)
          unless seconds_the_server_asked_to_wait.nil?
            return seconds_the_server_asked_to_wait.clamp(
              SHORTEST_WAIT_THE_SERVER_CAN_ASK_FOR_SECONDS, LONGEST_WAIT_THE_SERVER_CAN_ASK_FOR_SECONDS
            )
          end

          ceiling_seconds = 1 << [attempt, MAXIMUM_BACKOFF_EXPONENT].min
          fixed_seconds = ceiling_seconds / 2.0

          fixed_seconds + (random_fraction * (ceiling_seconds - fixed_seconds))
        end
      end
    end
  end
end
