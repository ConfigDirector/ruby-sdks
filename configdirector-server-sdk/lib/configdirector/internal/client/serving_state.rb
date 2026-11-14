# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class ServingState
        def initialize
          @lock = Mutex.new
          @first_values_no_longer_awaited = ConditionVariable.new
          @served_configs = nil
          @closed = false
          @connection_failed_unrecoverably = false
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
            replaced_configs = @served_configs
            unless arrival == :after_close
              @served_configs = served_configs
              @first_values_no_longer_awaited.broadcast
            end
            [arrival, replaced_configs]
          end
        end

        def close
          @lock.synchronize do
            @closed = true
            @served_configs = nil
            @first_values_no_longer_awaited.broadcast
          end
        end

        def expect_no_values_from_the_connection
          @lock.synchronize do
            @connection_failed_unrecoverably = true
            @first_values_no_longer_awaited.broadcast
          end
        end

        def timed_out_waiting_for_the_first_values?(timeout_seconds)
          @lock.synchronize do
            give_up_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
            loop do
              return false if @closed || !@served_configs.nil? || @connection_failed_unrecoverably

              remaining_seconds = give_up_at - Process.clock_gettime(Process::CLOCK_MONOTONIC)
              return true unless remaining_seconds.positive?

              @first_values_no_longer_awaited.wait(@lock, remaining_seconds)
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
