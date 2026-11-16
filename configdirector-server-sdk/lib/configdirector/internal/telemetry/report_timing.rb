# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      ReportTiming = Data.define(
        :seconds_before_the_first_report, :seconds_between_reports, :seconds_a_report_may_take
      )

      class ReportTiming
        def self.of_a_client_reporting_every(seconds_between_reports)
          new(
            seconds_before_the_first_report: 5, seconds_between_reports: seconds_between_reports,
            seconds_a_report_may_take: 5
          )
        end
      end
    end
  end
end
