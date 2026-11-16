# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Streaming
      class Heartbeats
        def initialize(endpoint:, timing:, log:)
          @endpoint = endpoint
          @timing = timing
          @log = log
          @lock = Mutex.new
          @session_id_of_the_open_stream = nil
        end

        def stream_opened(session_id)
          @lock.synchronize { @session_id_of_the_open_stream = session_id }
        end

        def stream_ended
          @lock.synchronize { @session_id_of_the_open_stream = nil }
        end

        def send_on_every_interval
          loop do
            StoppableThread.stoppable { sleep(@timing.seconds_between_heartbeats) }
            session_id = @lock.synchronize { @session_id_of_the_open_stream }
            send_for(session_id) unless session_id.nil?
          end
        end

        private

        def send_for(session_id)
          answer = StoppableThread.stoppable { answer_to_a_heartbeat_of(session_id) }
          @log.debug { "Heartbeat failed with status: #{answer.code}" } unless answer.is_a?(Net::HTTPSuccess)
        rescue StandardError => e
          @log.debug { "Heartbeat failed: #{e.class}: #{e.message}" }
        end

        def answer_to_a_heartbeat_of(session_id)
          http_session = @endpoint.http_session(@timing)
          @timing.deadline_of_a_heartbeat.ending_the_exchange_when_it_passes(http_session) do
            http_session.start do
              http_session.request(@endpoint.heartbeat_request(session_id: session_id)) { |response| break response }
            end
          end
        end
      end
    end
  end
end
