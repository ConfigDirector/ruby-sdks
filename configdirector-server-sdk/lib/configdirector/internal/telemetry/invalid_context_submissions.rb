# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      class InvalidContextSubmissions
        DISTINCT_KIND_SAMPLE_LIMIT = 20
        REASON = "invalid-context-kind"

        private_constant :REASON

        def initialize
          @counts_by_kind_sample = {}
          @count_beyond_the_sample_limit = 0
          @counted_since = nil
        end

        def count(kind_sample, now)
          @counted_since ||= now

          if @counts_by_kind_sample.key?(kind_sample) then count_known(kind_sample)
          elsif @counts_by_kind_sample.size < DISTINCT_KIND_SAMPLE_LIMIT then count_new(kind_sample)
          else count_beyond_the_sample_limit
          end
        end

        def wire_entries_taken_for_a_report(now)
          counted_since = @counted_since

          AggregatedWireEntries.of(
            counts_by_wire_event_taken_for_a_report, counted_since: counted_since, counted_until: now
          )
        end

        def discard
          @counts_by_kind_sample = {}
          @count_beyond_the_sample_limit = 0
          @counted_since = nil
        end

        private

        def count_known(kind_sample)
          @counts_by_kind_sample[kind_sample] += 1
          :known_kind_sample
        end

        def count_new(kind_sample)
          @counts_by_kind_sample[kind_sample] = 1
          :new_kind_sample
        end

        def count_beyond_the_sample_limit
          @count_beyond_the_sample_limit += 1
          @count_beyond_the_sample_limit == 1 ? :first_beyond_sample_limit : :beyond_sample_limit
        end

        def counts_by_wire_event_taken_for_a_report
          counts_by_wire_event = @counts_by_kind_sample.to_h do |kind_sample, count|
            [wire_event_of(kind_sample), count]
          end
          unless @count_beyond_the_sample_limit.zero?
            counts_by_wire_event[wire_event_of(nil)] = @count_beyond_the_sample_limit
          end
          discard

          counts_by_wire_event
        end

        def wire_event_of(kind_sample)
          { reason: REASON, kindSample: kind_sample }.compact
        end
      end
    end
  end
end
