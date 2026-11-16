# frozen_string_literal: true

require "json"
require "timeout"

module ConfigDirector
  module Internal
    module Polling
      class PollRequest
        MAXIMUM_BODY_MEBIBYTES = 32
        MAXIMUM_BODY_BYTES = MAXIMUM_BODY_MEBIBYTES * 1024 * 1024
        PAYLOAD_STATUS = 200
        SUCCESS_STATUSES = (200..299)
        TOO_MANY_REQUESTS_STATUS = 429
        CLIENT_ERROR_STATUSES = (400..499)

        private_constant :MAXIMUM_BODY_MEBIBYTES, :MAXIMUM_BODY_BYTES, :PAYLOAD_STATUS, :SUCCESS_STATUSES,
                         :TOO_MANY_REQUESTS_STATUS, :CLIENT_ERROR_STATUSES

        def initialize(endpoint:, session_id:, last_update_timestamp:, deadline:)
          @endpoint = endpoint
          @session_id = session_id
          @last_update_timestamp = last_update_timestamp
          @deadline = deadline
          @http_session = endpoint.http_session
          @body_text_read = ""
        end

        def answer
          answer_in(response_to_the_post)
        rescue Timeout::Error
          PollAnswer.timed_out(@deadline.description_of_having_passed)
        rescue StandardError => e
          PollAnswer.unanswered("#{e.class}: #{e.message}")
        end

        private

        def response_to_the_post
          @deadline.ending_the_exchange_when_it_passes(@http_session) do
            @http_session.start { response_read_until_over_the_limit }
          end
        end

        def response_read_until_over_the_limit
          @http_session.read_timeout = @deadline.seconds_left
          @http_session.request(json_post) do |response|
            @body_text_read = body_text_read_until_over_the_limit(response)
            break response
          end
        end

        def json_post
          @endpoint.json_post_of_a_poll(session_id: @session_id, last_update_timestamp: @last_update_timestamp)
        end

        def body_text_read_until_over_the_limit(response)
          body = String.new
          @http_session.read_timeout = @deadline.seconds_left
          response.read_body do |chunk|
            body << chunk
            break if body.bytesize > MAXIMUM_BODY_BYTES

            @http_session.read_timeout = @deadline.seconds_left
          end

          body.force_encoding(Encoding::UTF_8).scrub!
        end

        def answer_in(response)
          status = Integer(response.code, 10)

          case status
          when PAYLOAD_STATUS then answer_holding_the_payload
          when SUCCESS_STATUSES then PollAnswer.unchanged
          when TOO_MANY_REQUESTS_STATUS then PollAnswer.throttled(status, retry_after_seconds_in(response))
          when CLIENT_ERROR_STATUSES then PollAnswer.refused_unrecoverably(status, detail: refusal_detail)
          else PollAnswer.refused(status)
          end
        end

        def answer_holding_the_payload
          if @body_text_read.bytesize > MAXIMUM_BODY_BYTES
            return PollAnswer.unreadable("it is larger than #{MAXIMUM_BODY_MEBIBYTES} MiB")
          end

          payload = Value::ParsedJson.of(@body_text_read)
          return PollAnswer.unreadable("it is not a JSON object") unless payload.is_a?(Hash)

          timestamp = payload["timestamp"]
          PollAnswer.payload(@body_text_read, timestamp: timestamp.is_a?(String) ? timestamp : nil)
        rescue JSON::ParserError => e
          PollAnswer.unreadable(e.message)
        end

        def retry_after_seconds_in(response)
          Connection::RetryAfterHeader.seconds_to_wait(response["Retry-After"], Time.now)
        end

        def refusal_detail
          @endpoint.refusal_detail_in(@body_text_read)
        end
      end
    end
  end
end
