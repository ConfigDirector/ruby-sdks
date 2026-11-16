# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Streaming
      StreamEnd = Data.define(:kind, :cause, :status, :seconds_the_server_asked_to_wait, :last_event_id)

      class StreamEnd
        WHAT_FOLLOWS_BY_KIND = {
          unreachable: :reconnection_after_a_failed_attempt,
          refused: :reconnection_after_a_failed_attempt,
          throttled: :reconnection_after_a_failed_attempt,
          dropped: :reconnection_after_an_open_stream,
          refused_unrecoverably: :unrecoverable_error,
          ended_without_content: :no_reconnection
        }.freeze

        SUCCESS_STATUSES = (200..299)
        NO_CONTENT_STATUS = 204
        TOO_MANY_REQUESTS_STATUS = 429
        CLIENT_ERROR_STATUSES = (400..499)
        MILLISECONDS_PER_SECOND = 1000.0

        private_constant :WHAT_FOLLOWS_BY_KIND, :SUCCESS_STATUSES, :NO_CONTENT_STATUS, :TOO_MANY_REQUESTS_STATUS,
                         :CLIENT_ERROR_STATUSES, :MILLISECONDS_PER_SECOND

        def self.stream_opened_by?(status)
          SUCCESS_STATUSES.cover?(status) && status != NO_CONTENT_STATUS
        end

        def self.unreachable(cause, last_event_id:)
          new(kind: :unreachable, cause: cause, status: nil, seconds_the_server_asked_to_wait: nil,
              last_event_id: last_event_id)
        end

        def self.dropped(cause, milliseconds_named_by_the_stream:, last_event_id:)
          new(
            kind: :dropped, cause: cause, status: nil,
            seconds_the_server_asked_to_wait: milliseconds_named_by_the_stream&.fdiv(MILLISECONDS_PER_SECOND),
            last_event_id: last_event_id
          )
        end

        def self.answered_without_a_stream(status, seconds_named_by_retry_after:, last_event_id:)
          case status
          when NO_CONTENT_STATUS then without_a_stream(:ended_without_content, status, last_event_id)
          when TOO_MANY_REQUESTS_STATUS
            without_a_stream(:throttled, status, last_event_id, seconds_named_by_retry_after)
          when CLIENT_ERROR_STATUSES then without_a_stream(:refused_unrecoverably, status, last_event_id)
          else without_a_stream(:refused, status, last_event_id)
          end
        end

        def self.without_a_stream(kind, status, last_event_id, seconds_the_server_asked_to_wait = nil)
          new(
            kind: kind, cause: "the SDK server answered with status #{status}", status: status,
            seconds_the_server_asked_to_wait: seconds_the_server_asked_to_wait, last_event_id: last_event_id
          )
        end

        private_class_method :without_a_stream

        def what_follows
          WHAT_FOLLOWS_BY_KIND.fetch(kind)
        end
      end
    end
  end
end
