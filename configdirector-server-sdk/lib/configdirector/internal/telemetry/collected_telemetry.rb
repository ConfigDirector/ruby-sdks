# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      class CollectedTelemetry
        SHARE_OF_THE_EVENT_QUEUE_FOR_EVALUATIONS = 0.7
        SHARE_OF_THE_EVENT_QUEUE_FOR_CAPTURED_CONTEXTS = 0.3

        private_constant :SHARE_OF_THE_EVENT_QUEUE_FOR_EVALUATIONS, :SHARE_OF_THE_EVENT_QUEUE_FOR_CAPTURED_CONTEXTS

        def initialize(event_queue_limit)
          @evaluations_limit = (event_queue_limit * SHARE_OF_THE_EVENT_QUEUE_FOR_EVALUATIONS).ceil
          @captured_contexts_limit = (event_queue_limit * SHARE_OF_THE_EVENT_QUEUE_FOR_CAPTURED_CONTEXTS).floor
          @invalid_context_submissions = InvalidContextSubmissions.new
          @collecting_process_id = Process.pid
          discard_evaluations_and_captured_contexts
        end

        def add(evaluated_read)
          leave_to_the_parent_process_what_it_collected
          reported_context = ReportedContext.of(evaluated_read.evaluation.context)
          capture(reported_context) unless reported_context.nil?
          @evaluations_collected_since ||= Time.now
          @evaluations << ReportedEvaluation.of(evaluated_read)
          return unless @evaluations.length > @evaluations_limit

          @evaluations.shift
          @evaluations_dropped += 1
        end

        def count_invalid_context(kind_sample)
          leave_to_the_parent_process_what_it_collected
          @invalid_context_submissions.count(kind_sample, Time.now)
        end

        def keep_what_the_parent_process_collected
          @collecting_process_id = Process.pid
        end

        def taken_for_a_report
          leave_to_the_parent_process_what_it_collected
          taken_at = Time.now

          TelemetryReport.new(
            evaluations: @evaluations, evaluations_collected_since: @evaluations_collected_since,
            evaluations_dropped: @evaluations_dropped, captured_contexts: @captured_contexts.values,
            captured_contexts_dropped: @captured_contexts_dropped,
            invalid_context_wire_entries: @invalid_context_submissions.wire_entries_taken_for_a_report(taken_at),
            taken_at: taken_at
          ).tap { discard_evaluations_and_captured_contexts }
        end

        def discard_evaluations_and_captured_contexts
          @evaluations = []
          @evaluations_collected_since = nil
          @evaluations_dropped = 0
          @captured_contexts = {}
          @captured_contexts_dropped = 0
        end

        private

        def leave_to_the_parent_process_what_it_collected
          return if @collecting_process_id == Process.pid

          @collecting_process_id = Process.pid
          discard_evaluations_and_captured_contexts
          @invalid_context_submissions.discard
        end

        def capture(reported_context)
          @captured_contexts[[reported_context.kind, reported_context.identifier]] = reported_context
          return unless @captured_contexts.size > @captured_contexts_limit

          @captured_contexts.shift
          @captured_contexts_dropped += 1
        end
      end
    end
  end
end
