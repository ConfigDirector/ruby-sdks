# frozen_string_literal: true

require "timeout"
require "uri"

module ConfigDirector
  module Internal
    module Telemetry
      class TelemetryEndpoint
        def initialize(url:, server_sdk_key:, metadata:, sdk_identity:, seconds_a_report_may_take:)
          @telemetry_uri = URI("#{url.delete_suffix("/")}/server/telemetry/v1")
          @server_sdk_key = server_sdk_key
          @sdk_identity = sdk_identity
          @meta_context = sdk_identity.meta_context_of_an_application_with(metadata)
          @seconds_a_report_may_take = seconds_a_report_may_take
        end

        def answer_to(report)
          json_post = json_post_of(report)

          answer_before(Connection::RequestDeadline.on_the_clock_of_the_process(@seconds_a_report_may_take), json_post)
        end

        private

        def answer_before(deadline, json_post)
          ReportAnswer.with_status(Integer(response_to(json_post, deadline).code, 10))
        rescue Timeout::Error
          ReportAnswer.unanswered(deadline.description_of_having_passed)
        rescue StandardError => e
          ReportAnswer.unanswered("#{e.class}: #{e.message}")
        end

        def json_post_of(report)
          Connection::JsonPostRequest.carrying(
            CompactJsonText.of({ serverSdkKey: @server_sdk_key, metaContext: @meta_context, **report.wire_events }),
            @telemetry_uri, @sdk_identity
          )
        end

        def response_to(json_post, deadline)
          http_session = Connection::HttpSession.to(@telemetry_uri)
          http_session.open_timeout = deadline.seconds_left
          http_session.start do
            http_session.write_timeout = deadline.seconds_left
            http_session.read_timeout = deadline.seconds_left
            http_session.request(json_post) { |response| break response }
          end
        end
      end
    end
  end
end
