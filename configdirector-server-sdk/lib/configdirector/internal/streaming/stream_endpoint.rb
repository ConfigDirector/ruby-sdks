# frozen_string_literal: true

require "uri"

module ConfigDirector
  module Internal
    module Streaming
      class StreamEndpoint
        def initialize(url:, server_sdk_key:, metadata:, sdk_identity:)
          base_url = url.delete_suffix("/")
          @stream_uri = URI("#{base_url}/server/sse/v1")
          @heartbeat_uri = URI("#{base_url}/server/heartbeat/v1")
          @server_sdk_key = server_sdk_key
          @sdk_identity = sdk_identity
          @meta_context = sdk_identity.meta_context_of_an_application_with(metadata)
        end

        def http_session(timing)
          http_session = Connection::HttpSession.to(@stream_uri)
          http_session.open_timeout = timing.seconds_to_open_a_stream
          http_session.read_timeout = timing.seconds_of_silence_of_a_dropped_stream
          http_session
        end

        def stream_request(session_id:, last_event_id:)
          request = Connection::JsonPostRequest.to(
            @stream_uri, @sdk_identity,
            serverSdkKey: @server_sdk_key, sessionId: session_id, metaContext: @meta_context
          )
          request["Accept"] = "text/event-stream"
          request["Last-Event-ID"] = last_event_id unless last_event_id.empty?
          request
        end

        def heartbeat_request(session_id:)
          Connection::JsonPostRequest.to(
            @heartbeat_uri, @sdk_identity, serverSdkKey: @server_sdk_key, sessionId: session_id
          )
        end
      end
    end
  end
end
