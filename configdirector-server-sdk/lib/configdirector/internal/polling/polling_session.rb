# frozen_string_literal: true

require "securerandom"

module ConfigDirector
  module Internal
    module Polling
      class PollingSession
        def initialize(endpoint:, timing:, log:)
          @endpoint = endpoint
          @timing = timing
          @log = log
          @session_id = SecureRandom.uuid
          @last_update_timestamp = nil
          @seconds_before_the_next_poll = timing.seconds_between_polls
        end

        def poll(report_unrecoverable_error, deliver_payload_text)
          answer = answer_retried_once_when_unanswered
          @seconds_before_the_next_poll = answer.seconds_before_the_next_poll(@timing.seconds_between_polls)
          what_follows = answer.what_follows

          case what_follows
          when :delivery then what_follows = deliver(answer, deliver_payload_text)
          when :no_delivery then nil
          when :error_log then log_the_failure_of(answer)
          when :end_of_polling then log_and_report_the_unrecoverable_error_of(answer, report_unrecoverable_error)
          end

          what_follows
        end

        def poll_on_every_interval(report_unrecoverable_error, deliver_payload_text)
          loop do
            StoppableThread.stoppable { @timing.pause_before_the_next_poll.call(@seconds_before_the_next_poll) }
            break if poll(report_unrecoverable_error, deliver_payload_text) == :end_of_polling
          end
        end

        private

        def answer_retried_once_when_unanswered
          deadline = PollDeadline.new(@timing)
          answer = answer_before(deadline)
          return answer unless answer.sent_again_at_once?

          @log.debug { "The poll got no answer and is sent again at once" }
          answer_before(deadline)
        end

        def answer_before(deadline)
          request = PollRequest.new(
            endpoint: @endpoint, session_id: @session_id, last_update_timestamp: @last_update_timestamp,
            deadline: deadline
          )

          StoppableThread.stoppable { request.answer }
        end

        def deliver(answer, deliver_payload_text)
          deliver_payload_text.call(answer.payload_text.to_s)
          @last_update_timestamp = answer.timestamp || @last_update_timestamp
          :delivery
        rescue StandardError => e
          log_the_failure_of(PollAnswer.unreadable("#{e.class}: #{e.message.inspect}"))
          :error_log
        end

        def log_the_failure_of(answer)
          @log.error("Error during polling: #{answer.failure_message}")
        end

        def log_and_report_the_unrecoverable_error_of(answer, report_unrecoverable_error)
          error = ConfigDirectorConnectionError.new(answer.failure_message, status: answer.status)
          @log.error(error.message)
          report_unrecoverable_error.call(error)
        end
      end
    end
  end
end
