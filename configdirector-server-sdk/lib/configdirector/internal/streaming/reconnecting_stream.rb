# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Streaming
      class ReconnectingStream
        ATTEMPTS_LOGGED_AT_INFO = 5

        private_constant :ATTEMPTS_LOGGED_AT_INFO

        def initialize(endpoint:, timing:, heartbeats:, log:)
          @endpoint = endpoint
          @timing = timing
          @heartbeats = heartbeats
          @log = log
          @attempt = 0
          @last_event_id = ""
        end

        def keep_open(report_unrecoverable_error:, &deliver_event_data)
          loop do
            stream_end = stream_until_it_ends(&deliver_event_data)
            @last_event_id = stream_end.last_event_id
            case stream_end.what_follows
            when :no_reconnection then return
            when :unrecoverable_error then return stop_for_good(stream_end.status, report_unrecoverable_error)
            when :reconnection_after_an_open_stream then pause_before_attempt(1, stream_end)
            when :reconnection_after_a_failed_attempt then pause_before_attempt(@attempt + 1, stream_end)
            end
          end
        end

        private

        def stream_until_it_ends(&deliver_event_data)
          connection = StreamConnection.new(
            endpoint: @endpoint, timing: @timing, last_event_id: @last_event_id
          ) { |event_data| deliver(event_data, &deliver_event_data) }
          stream_end = connection.stream_until_it_ends { take_note_of_the_open_stream_of(connection) }
          @log.debug { "Disconnected: #{stream_end.cause}" }
          stream_end
        ensure
          @heartbeats.stream_ended
        end

        def take_note_of_the_open_stream_of(connection)
          @heartbeats.stream_opened(connection.session_id)
          @log.debug { "Connected" }
        end

        def deliver(event_data)
          begin
            yield event_data
          rescue StandardError => e
            @log.error("Error parsing and dispatching config data update: #{e.class}: #{e.message.inspect}")
          end
          StoppableThread.stop_here_if_asked_to
        end

        def stop_for_good(status, report_unrecoverable_error)
          error = ConfigDirectorConnectionError.new(
            "Connection failed with status: #{status}. This is an unrecoverable error, will not attempt to reconnect.",
            status: status
          )
          @log.error(error.message)
          report_unrecoverable_error.call(error)
        end

        def pause_before_attempt(attempt, stream_end)
          @attempt = attempt
          seconds = ReconnectionDelay.seconds_before_attempt(
            attempt, seconds_the_server_asked_to_wait: stream_end.seconds_the_server_asked_to_wait,
                     random_fraction: @timing.random_fraction.call
          )
          line = "Scheduling reconnect attempt ##{attempt} in #{format("%g", seconds)} seconds."
          attempt > ATTEMPTS_LOGGED_AT_INFO ? @log.warn(line) : @log.info(line)
          StoppableThread.stoppable { @timing.pause_before_reconnecting.call(seconds) }
        end
      end
    end
  end
end
