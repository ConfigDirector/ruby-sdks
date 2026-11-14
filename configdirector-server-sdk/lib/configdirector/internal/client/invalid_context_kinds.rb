# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class InvalidContextKinds
        DISTINCT_KIND_SAMPLE_LIMIT = 20

        def initialize
          @mutex = Mutex.new
          @kind_samples = Set.new
          @a_kind_was_beyond_the_sample_limit = false
        end

        def record(kind_sample)
          @mutex.synchronize do
            if @kind_samples.include?(kind_sample) then :known_kind_sample
            elsif @kind_samples.size < DISTINCT_KIND_SAMPLE_LIMIT then record_new(kind_sample)
            elsif @a_kind_was_beyond_the_sample_limit then :beyond_sample_limit
            else record_first_beyond_the_sample_limit
            end
          end
        end

        private

        def record_new(kind_sample)
          @kind_samples << kind_sample
          :new_kind_sample
        end

        def record_first_beyond_the_sample_limit
          @a_kind_was_beyond_the_sample_limit = true
          :first_beyond_sample_limit
        end
      end
    end
  end
end
