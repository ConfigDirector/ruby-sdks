# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      class ReportedTelemetry
        COLLECTS_BY_REPORTING = {
          not_started: true,
          on_the_schedule: true,
          stopped_by_a_refusal: false,
          closed: false
        }.freeze

        REPORTER_OF_WHAT_THE_PARENT_PROCESS_COLLECTED_BY_WHAT_FORKED = {
          fork: :parent_process,
          daemon: :forked_process
        }.freeze

        private_constant :COLLECTS_BY_REPORTING, :REPORTER_OF_WHAT_THE_PARENT_PROCESS_COLLECTED_BY_WHAT_FORKED

        def self.for_a_client_with(
          server_sdk_key:, metadata:, connection_options:, telemetry_options:, sdk_identity:, logger:
        )
          reporting_to(
            url: connection_options.url, server_sdk_key: server_sdk_key, metadata: metadata,
            sdk_identity: sdk_identity, event_queue_limit: telemetry_options.event_queue_limit,
            timing: ReportTiming.of_a_client_reporting_every(telemetry_options.flush_interval), logger: logger
          )
        end

        def self.reporting_to(url:, server_sdk_key:, metadata:, sdk_identity:, event_queue_limit:, timing:, logger:)
          endpoint = TelemetryEndpoint.new(
            url: url, server_sdk_key: server_sdk_key, metadata: metadata, sdk_identity: sdk_identity,
            seconds_a_report_may_take: timing.seconds_a_report_may_take
          )

          new(
            reporter: EventReporter.new(endpoint, logger),
            collected_telemetry: CollectedTelemetry.new(event_queue_limit), schedule: ReportSchedule.new(timing),
            logger: logger
          )
        end

        def initialize(reporter:, collected_telemetry:, schedule:, logger:)
          @reporter = reporter
          @collected_telemetry = collected_telemetry
          @schedule = schedule
          @log = Logging::ClientLog.new(logger, component: "TelemetryEventCollector")
          @lock = Mutex.new
          @reporting = :not_started
        end

        def record(evaluated_read)
          @lock.synchronize { @collected_telemetry.add(evaluated_read) if COLLECTS_BY_REPORTING.fetch(@reporting) }
          nil
        end

        def count_invalid_context(kind_sample)
          @lock.synchronize { @collected_telemetry.count_invalid_context(kind_sample) }
        end

        def start_reporting
          @lock.synchronize do
            return unless @reporting == :not_started

            @reporting = :on_the_schedule
            @schedule.start { report_what_was_collected }
          end
          nil
        end

        def restart_in_a_forked_process(forked_through)
          case REPORTER_OF_WHAT_THE_PARENT_PROCESS_COLLECTED_BY_WHAT_FORKED.fetch(forked_through)
          when :parent_process then nil
          when :forked_process then @collected_telemetry.keep_what_the_parent_process_collected
          end
          @schedule.start { report_what_was_collected } if @reporting == :on_the_schedule
          nil
        end

        def close
          last_report = @lock.synchronize do
            last_report = COLLECTS_BY_REPORTING.fetch(@reporting) ? @collected_telemetry.taken_for_a_report : nil
            @reporting = :closed

            last_report
          end

          @schedule.stop
          @schedule.wait_for_a_report_being_sent
          send_to_the_endpoint(last_report) unless last_report.nil?
          nil
        end

        private

        def report_what_was_collected
          report = @lock.synchronize do
            @reporting == :on_the_schedule ? @collected_telemetry.taken_for_a_report : nil
          end

          send_to_the_endpoint(report) unless report.nil?
        end

        def send_to_the_endpoint(report)
          return if report.empty?

          case @reporter.what_follows_a_report_of(report)
          when :more_reports then nil
          when :no_more_reports then stop_collecting
          end
        rescue StandardError => e
          @log.warn("Error flushing telemetry events: #{e.class}: #{e.message.inspect}")
        end

        def stop_collecting
          @lock.synchronize do
            @reporting = :stopped_by_a_refusal if @reporting == :on_the_schedule
            @collected_telemetry.discard_evaluations_and_captured_contexts
          end
          @schedule.stop
        end
      end
    end
  end
end
