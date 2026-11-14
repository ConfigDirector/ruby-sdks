# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Streaming
      StreamTiming = Data.define(
        :seconds_between_heartbeats,
        :seconds_of_silence_of_a_dropped_stream,
        :seconds_to_open_a_stream,
        :pause_before_reconnecting,
        :random_fraction
      )

      class StreamTiming
        def self.of_the_protocol
          new(
            seconds_between_heartbeats: 90,
            seconds_of_silence_of_a_dropped_stream: 45,
            seconds_to_open_a_stream: 10,
            pause_before_reconnecting: ->(seconds) { sleep(seconds) },
            random_fraction: -> { Random.rand }
          )
        end
      end
    end
  end
end
