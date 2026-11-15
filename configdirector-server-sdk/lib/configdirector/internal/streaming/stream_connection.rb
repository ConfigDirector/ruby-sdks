# frozen_string_literal: true

require "securerandom"

module ConfigDirector
  module Internal
    module Streaming
      class StreamConnection
        attr_reader :session_id

        def initialize(endpoint:, timing:, last_event_id:, &event_data_received)
          @endpoint = endpoint
          @timing = timing
          @session_id = SecureRandom.uuid
          @last_event_id_sent = last_event_id
          @parser = ServerSentEvents::EventStreamParser.new(last_event_id: last_event_id) do |event|
            event_data_received.call(event.data)
          end
          @answer = nil
        end

        def stream_until_it_ends(&stream_opened)
          StoppableThread.stoppable { request_the_stream(stream_opened) }

          stream_end_caused_by("the SDK server closed the stream")
        rescue StandardError => e
          stream_end_caused_by("#{e.class}: #{e.message}")
        end

        private

        def request_the_stream(stream_opened)
          http_session = @endpoint.http_session(@timing)
          request = @endpoint.stream_request(session_id: @session_id, last_event_id: @last_event_id_sent)
          http_session.start do
            http_session.request(request) do |response|
              @answer = response
              break unless StreamEnd.stream_opened_by?(status_of(response))

              read_the_stream_in(response, stream_opened)
            end
          end
        end

        def read_the_stream_in(response, stream_opened)
          StoppableThread.unstoppable { stream_opened.call }
          response.read_body { |chunk| StoppableThread.unstoppable { @parser.feed(chunk) } }
        end

        def stream_end_caused_by(cause)
          answer = @answer
          return StreamEnd.unreachable(cause, last_event_id: @parser.last_event_id) if answer.nil?
          return dropped_stream_end_caused_by(cause) if StreamEnd.stream_opened_by?(status_of(answer))

          seconds_named_by_retry_after = Connection::RetryAfterHeader.seconds_to_wait(answer["Retry-After"], Time.now)
          StreamEnd.answered_without_a_stream(
            status_of(answer), seconds_named_by_retry_after: seconds_named_by_retry_after,
                               last_event_id: @parser.last_event_id
          )
        end

        def status_of(answer)
          Integer(answer.code, 10)
        end

        def dropped_stream_end_caused_by(cause)
          StreamEnd.dropped(
            cause, milliseconds_named_by_the_stream: @parser.retry_milliseconds, last_event_id: @parser.last_event_id
          )
        end
      end
    end
  end
end
