# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      class EventReporter
        WHAT_FOLLOWS_BY_ANSWER_KIND = {
          accepted: :more_reports,
          refused: :more_reports,
          unanswered: :more_reports,
          refused_unrecoverably: :no_more_reports
        }.freeze

        LOG_BY_ANSWER_KIND = {
          accepted: ->(log, _answer) { log.debug { "Telemetry report successfully sent." } },
          refused: lambda do |log, answer|
            log.warn(
              "The telemetry endpoint responded with status #{answer.status}. " \
              "The events in this report were discarded."
            )
          end,
          unanswered: ->(log, answer) { log.warn("Error attempting to send telemetry data: #{answer.detail}") },
          refused_unrecoverably: lambda do |log, answer|
            log.warn(
              "Received a fatal status response (#{answer.status}) from the telemetry endpoint. " \
              "No more telemetry data will be sent."
            )
          end
        }.freeze

        private_constant :WHAT_FOLLOWS_BY_ANSWER_KIND, :LOG_BY_ANSWER_KIND

        def initialize(endpoint, logger)
          @endpoint = endpoint
          @log = Logging::ClientLog.new(logger, component: "EventReporter")
        end

        def what_follows_delivering(report)
          answer = @endpoint.answer_to(report)
          LOG_BY_ANSWER_KIND.fetch(answer.kind).call(@log, answer)

          WHAT_FOLLOWS_BY_ANSWER_KIND.fetch(answer.kind)
        end
      end
    end
  end
end
