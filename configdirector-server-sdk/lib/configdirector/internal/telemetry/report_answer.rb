# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      ReportAnswer = Data.define(:kind, :status, :detail)

      class ReportAnswer
        ACCEPTED_STATUSES = (200..299)
        REPORT_TOO_LARGE_STATUS = 413
        TOO_MANY_REQUESTS_STATUS = 429
        STATUSES_THAT_END_TELEMETRY = ((400..499).to_a - [REPORT_TOO_LARGE_STATUS, TOO_MANY_REQUESTS_STATUS]).freeze

        private_constant :ACCEPTED_STATUSES, :REPORT_TOO_LARGE_STATUS, :TOO_MANY_REQUESTS_STATUS,
                         :STATUSES_THAT_END_TELEMETRY

        def self.with_status(status)
          case status
          when ACCEPTED_STATUSES then new(kind: :accepted, status: status, detail: nil)
          when *STATUSES_THAT_END_TELEMETRY then new(kind: :refused_unrecoverably, status: status, detail: nil)
          else new(kind: :refused, status: status, detail: nil)
          end
        end

        def self.unanswered(detail)
          new(kind: :unanswered, status: nil, detail: detail)
        end
      end
    end
  end
end
