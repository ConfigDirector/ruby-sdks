# frozen_string_literal: true

require "uri"

module ConfigDirector
  module Internal
    module Polling
      class PollingEndpoint
        def initialize(url:, server_sdk_key:, metadata:)
          @poll_uri = URI("#{url.delete_suffix("/")}/server/polling/v1")
          @server_sdk_key = server_sdk_key
          @meta_context = Connection::SdkIdentity.meta_context_of_an_application_with(metadata)
        end

        def http_session
          http_session = Connection::HttpSession.to(@poll_uri)
          http_session.ignore_eof = false
          http_session
        end

        def json_post_of_a_poll(session_id:, last_update_timestamp:)
          Connection::JsonPostRequest.to(
            @poll_uri,
            **{
              serverSdkKey: @server_sdk_key, sessionId: session_id, metaContext: @meta_context,
              lastUpdateTimestamp: last_update_timestamp
            }.compact
          )
        end

        def refusal_detail_in(answer_body)
          RefusalDetail.in(answer_body, @server_sdk_key)
        end
      end
    end
  end
end
