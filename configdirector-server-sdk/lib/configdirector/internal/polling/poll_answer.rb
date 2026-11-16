# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Polling
      PollAnswer = Data.define(
        :kind, :payload_text, :timestamp, :failure_message, :status, :seconds_named_by_retry_after
      )

      class PollAnswer
        WHAT_FOLLOWS_BY_KIND = {
          payload: :delivery,
          unchanged: :no_delivery,
          unanswered: :error_log,
          timed_out: :error_log,
          refused: :error_log,
          throttled: :error_log,
          unreadable: :error_log,
          refused_unrecoverably: :end_of_polling
        }.freeze

        SENT_AGAIN_AT_ONCE_BY_KIND = {
          payload: false,
          unchanged: false,
          unanswered: true,
          timed_out: false,
          refused: false,
          throttled: false,
          unreadable: false,
          refused_unrecoverably: false
        }.freeze

        LONGEST_WAIT_THE_SERVER_CAN_ASK_FOR_SECONDS = 3600

        private_constant :WHAT_FOLLOWS_BY_KIND, :SENT_AGAIN_AT_ONCE_BY_KIND,
                         :LONGEST_WAIT_THE_SERVER_CAN_ASK_FOR_SECONDS

        def self.payload(payload_text, timestamp:)
          new(
            kind: :payload, payload_text: payload_text, timestamp: timestamp, failure_message: nil, status: nil,
            seconds_named_by_retry_after: nil
          )
        end

        def self.unchanged
          new(
            kind: :unchanged, payload_text: nil, timestamp: nil, failure_message: nil, status: nil,
            seconds_named_by_retry_after: nil
          )
        end

        def self.unanswered(cause)
          failed(:unanswered, "Connection failed with error: #{cause}.")
        end

        def self.timed_out(description_of_the_deadline_having_passed)
          failed(:timed_out, "Connection failed with error: #{description_of_the_deadline_having_passed}.")
        end

        def self.refused(status)
          failed(:refused, "Connection failed with status: #{status}", status: status)
        end

        def self.throttled(status, seconds_named_by_retry_after)
          failed(
            :throttled, "Connection failed with status: #{status}",
            status: status, seconds_named_by_retry_after: seconds_named_by_retry_after
          )
        end

        def self.refused_unrecoverably(status, detail:)
          failed(
            :refused_unrecoverably,
            "Connection failed with status: #{status}#{" (#{detail})" unless detail.empty?}. " \
            "This is an unrecoverable error, retry attempts will be ignored.",
            status: status
          )
        end

        def self.unreadable(cause)
          failed(:unreadable, "Failed to parse the response from the server: #{cause}")
        end

        def self.failed(kind, failure_message, status: nil, seconds_named_by_retry_after: nil)
          new(
            kind: kind, payload_text: nil, timestamp: nil, failure_message: failure_message, status: status,
            seconds_named_by_retry_after: seconds_named_by_retry_after
          )
        end

        private_class_method :failed

        def what_follows
          WHAT_FOLLOWS_BY_KIND.fetch(kind)
        end

        def sent_again_at_once?
          SENT_AGAIN_AT_ONCE_BY_KIND.fetch(kind)
        end

        def seconds_before_the_next_poll(seconds_between_polls)
          seconds_the_server_asked_for = [
            seconds_named_by_retry_after || 0, LONGEST_WAIT_THE_SERVER_CAN_ASK_FOR_SECONDS
          ].min

          [seconds_between_polls, seconds_the_server_asked_for].max
        end
      end
    end
  end
end
