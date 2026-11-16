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

          new(endpoint, logger)
        end

        def initialize(endpoint, logger)
          @endpoint = endpoint
          @logger = logger
          @log = Logging::ClientLog.new(logger, component: "StreamingTransport")
          @transport = transport_of_a_new_session
        end

        def open(report_unrecoverable_error:, &deliver_payload)
          open_a_stream(report_unrecoverable_error: report_unrecoverable_error, &deliver_payload)

          :values_awaited
        end

        def restart_in_a_forked_process(report_unrecoverable_error:, &deliver_payload)
          @transport = transport_of_a_new_session
          open_a_stream(report_unrecoverable_error: report_unrecoverable_error, &deliver_payload)
        end

        def close
          @transport.close
        end

        private

        def transport_of_a_new_session
          StreamingTransport.new(endpoint: @endpoint, logger: @logger)
        end

        def open_a_stream(report_unrecoverable_error:)
          @transport.open(report_unrecoverable_error: report_unrecoverable_error) do |event_data|
            payload = payload_or_nothing_in(event_data)
            yield payload unless payload.nil?
          end
        end

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
