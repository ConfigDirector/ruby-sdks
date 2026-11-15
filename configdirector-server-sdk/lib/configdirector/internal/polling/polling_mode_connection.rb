# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Polling
      class PollingModeConnection
        OPENING_BY_WHAT_FOLLOWS_THE_FIRST_POLL = {
          delivery: :values_awaited,
          no_delivery: :values_awaited,
          error_log: :first_attempt_failed,
          end_of_polling: :first_attempt_failed
        }.freeze

        private_constant :OPENING_BY_WHAT_FOLLOWS_THE_FIRST_POLL

        def self.for_a_client_with(server_sdk_key:, metadata:, connection_options:, sdk_identity:, logger:)
          endpoint = PollingEndpoint.new(
            url: connection_options.url, server_sdk_key: server_sdk_key, metadata: metadata,
            sdk_identity: sdk_identity
          )
          polling_interval = Connection::PollingInterval.new(configured_seconds: connection_options.polling_interval)
          timing = PollTiming.on_the_clock_of_the_process(
            seconds_between_polls: polling_interval.seconds, seconds_a_poll_may_take: connection_options.timeout
          )

          new(PollingTransport.new(endpoint: endpoint, timing: timing, logger: logger))
        end

        def initialize(transport)
          @transport = transport
        end

        def open(report_unrecoverable_error:, &deliver_payload)
          what_follows_the_first_poll = @transport.open(
            report_unrecoverable_error: report_unrecoverable_error
          ) { |payload_text| deliver_payload.call(Connection::ServerSdkPayloadParser.payload_in(payload_text)) }

          OPENING_BY_WHAT_FOLLOWS_THE_FIRST_POLL.fetch(what_follows_the_first_poll)
        end

        def restart_in_a_forked_process(report_unrecoverable_error:, &deliver_payload)
          @transport.restart_in_a_forked_process(
            report_unrecoverable_error: report_unrecoverable_error
          ) { |payload_text| deliver_payload.call(Connection::ServerSdkPayloadParser.payload_in(payload_text)) }
        end

        def close
          @transport.close
        end
      end
    end
  end
end
