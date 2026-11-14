# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class ServingState
        def initialize
          @lock = Mutex.new
          @values_arrived_or_client_closed = ConditionVariable.new
          @served_configs = nil
          @closed = false
        end

        def served_configs
          @lock.synchronize { @served_configs }
        end

        def closed?
          @lock.synchronize { @closed }
        end

        def serve(served_configs)
          @lock.synchronize do
            arrival = arrival_of_values
            unless arrival == :after_close
              @served_configs = served_configs
              @values_arrived_or_client_closed.broadcast
            end
            arrival
          end
        end

        def close
          @lock.synchronize do
            @closed = true
            @served_configs = nil
            @values_arrived_or_client_closed.broadcast
          end
        end

        def timed_out_waiting_for_the_first_values?(timeout_seconds)
          @lock.synchronize do
            give_up_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
            loop do
              return false if @closed || !@served_configs.nil?

              remaining_seconds = give_up_at - Process.clock_gettime(Process::CLOCK_MONOTONIC)
              return true unless remaining_seconds.positive?

              @values_arrived_or_client_closed.wait(@lock, remaining_seconds)
            end
          end
        end

        private

        def arrival_of_values
          if @closed then :after_close
          elsif @served_configs.nil? then :first_values
          else :newer_values
          end
        end
      end
    end
  end
end
