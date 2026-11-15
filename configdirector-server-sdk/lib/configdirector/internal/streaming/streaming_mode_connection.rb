# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Streaming
      class StreamingModeConnection
        def self.for_a_client_with(server_sdk_key:, metadata:, connection_options:, sdk_identity:, logger:)
          endpoint = StreamEndpoint.new(
            url: connection_options.url, server_sdk_key: server_sdk_key, metadata: metadata,
            sdk_identity: sdk_identity
          )

          new(
            StreamingTransport.new(endpoint: endpoint, logger: logger),
            Logging::ClientLog.new(logger, component: "StreamingTransport")
          )
        end

        def initialize(transport, log)
          @transport = transport
          @log = log
        end

        def open(report_unrecoverable_error:, &deliver_payload)
          @transport.open(report_unrecoverable_error: report_unrecoverable_error) do |event_data|
            payload = payload_or_nothing_in(event_data)
            deliver_payload.call(payload) unless payload.nil?
          end

          :values_awaited
        end

        def close
          @transport.close
        end

        private

        def payload_or_nothing_in(event_data)
          Connection::ServerSdkPayloadParser.payload_in(event_data)
        rescue Connection::NotAServerSdkPayload => e
          @log.debug { "Skipping a message that is not a server SDK payload: #{e.message}" }
          nil
        end
      end
    end
  end
end
