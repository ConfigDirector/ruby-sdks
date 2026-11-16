# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      class ReportSchedule
        def initialize(timing)
          @timing = timing
          @lock = Mutex.new
          @no_longer_waiting_for_the_next_report = ConditionVariable.new
          @stopped = true
          @thread = nil
        end

        def start(&send_a_report)
          return if @thread&.alive?

          @stopped = false
          thread = Thread.new { send_a_report_on_every_interval(send_a_report) }
          thread.name = "configdirector-telemetry"
          @thread = thread
          nil
        end

        def stop
          @lock.synchronize do
            @stopped = true
            @no_longer_waiting_for_the_next_report.broadcast
          end
          nil
        end

        def wait_for_a_report_being_sent
          thread = @lock.synchronize { @thread }
          thread&.join(@timing.seconds_a_report_may_take) unless thread.equal?(Thread.current)
          nil
        end

        private

        def send_a_report_on_every_interval(send_a_report)
          seconds_before_the_next_report = @timing.seconds_before_the_first_report

          until stopped_within?(seconds_before_the_next_report)
            send_a_report.call
            seconds_before_the_next_report = @timing.seconds_between_reports
          end
        end

        def stopped_within?(seconds)
          next_report_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds

          @lock.synchronize do
            loop do
              return true if @stopped

              seconds_left = next_report_at - Process.clock_gettime(Process::CLOCK_MONOTONIC)
              return false unless seconds_left.positive?

              @no_longer_waiting_for_the_next_report.wait(@lock, seconds_left)
            end
          end
        end
      end
    end
  end
end
