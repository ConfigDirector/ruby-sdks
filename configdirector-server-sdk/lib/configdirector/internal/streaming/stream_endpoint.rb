# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module ConfigDirector
  module Internal
    module Streaming
      class StreamEndpoint
        SDK_NAME = "ruby-server-sdk"

        private_constant :SDK_NAME

        def initialize(url:, server_sdk_key:, metadata:)
          base_url = url.delete_suffix("/")
          @stream_uri = URI("#{base_url}/server/sse/v1")
          @heartbeat_uri = URI("#{base_url}/server/heartbeat/v1")
          @server_sdk_key = server_sdk_key
          @meta_context = {
            sdkName: SDK_NAME, sdkVersion: VERSION, appName: metadata.app_name, appVersion: metadata.app_version
          }.compact
        end

        def http_session(timing)
          http_session = Net::HTTP.new(@stream_uri.hostname.to_s, @stream_uri.port)
          http_session.use_ssl = @stream_uri.scheme == "https"
          http_session.open_timeout = timing.seconds_to_open_a_stream
          http_session.read_timeout = timing.seconds_of_silence_of_a_dropped_stream
          http_session
        end

        def stream_request(session_id:, last_event_id:)
          request = json_post_to(
            @stream_uri, serverSdkKey: @server_sdk_key, sessionId: session_id, metaContext: @meta_context
          )
          request["Accept"] = "text/event-stream"
          request["Last-Event-ID"] = last_event_id unless last_event_id.empty?
          request
        end

        def heartbeat_request(session_id:)
          json_post_to(@heartbeat_uri, serverSdkKey: @server_sdk_key, sessionId: session_id)
        end

        private

        def json_post_to(uri, **body)
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request["User-Agent"] = "#{SDK_NAME}/#{VERSION}"
          request.body = JSON.generate(body)
          request
        end
      end
    end
  end
end
