# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Streaming
      class StreamingTransport
        SECONDS_CLOSE_WAITS_FOR_THE_THREADS = 5

        private_constant :SECONDS_CLOSE_WAITS_FOR_THE_THREADS

        def initialize(endpoint:, logger:, timing: StreamTiming.of_the_protocol)
          log = Logging::ClientLog.new(logger, component: "StreamingTransport")
          @heartbeats = Heartbeats.new(endpoint: endpoint, timing: timing, log: log)
          @stream = ReconnectingStream.new(endpoint: endpoint, timing: timing, heartbeats: @heartbeats, log: log)
          @lock = Mutex.new
          @threads = []
        end

        def open(report_unrecoverable_error:, &deliver_event_data)
          @lock.synchronize do
            heartbeat_thread = StoppableThread.start("configdirector-heartbeat") { @heartbeats.send_on_every_interval }
            stream_thread = StoppableThread.start("configdirector-streaming") do
              @stream.keep_open(report_unrecoverable_error: report_unrecoverable_error, &deliver_event_data)
            ensure
              heartbeat_thread.stop
            end
            @threads = [stream_thread, heartbeat_thread]
          end
        end

        def close
          threads = @lock.synchronize { @threads }
          threads.each(&:stop)
          give_up_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SECONDS_CLOSE_WAITS_FOR_THE_THREADS
          threads.each do |thread|
            thread.join_within([give_up_at - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max)
          end
        end
      end
    end
  end
end
