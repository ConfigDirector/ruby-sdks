# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      class TestClientInitializations
        def initialize(lock, timeout_seconds)
          @lock = lock
          @timeout_seconds = timeout_seconds
          @settled = ConditionVariable.new
          @state = :not_connected
          @next_initialization = :serves_the_values
          @held_until_monotonic_seconds = 0.0
          @outcome_of_the_held_initialization = :awaited
        end

        def connected?
          @state == :connected
        end

        def hold_the_next_initialization
          @next_initialization = :is_held
          nil
        end

        def serve_the_values_at_the_next_initialization
          @next_initialization = :serves_the_values
        end

        def begin_the_next_initialization
          next_initialization = @next_initialization
          @next_initialization = :serves_the_values
          case next_initialization
          when :serves_the_values then @state = :connected
          when :fails then @state = :not_connected
          when :is_held then hold
          end

          next_initialization
        end

        def complete_initialization
          case @state
          when :holding_an_initialization
            @state = :connected
            :held_initialization_completed
          when :not_connected, :connected
            cancel_a_hold_of_the_next_initialization
            :no_initialization_held
          end
        end

        def fail_initialization
          case @state
          when :holding_an_initialization
            @state = :not_connected
            :held_initialization_failed
          when :not_connected, :connected
            @next_initialization = :fails
            :next_initialization_fails
          end
        end

        def settling_the_held_initialization(outcome)
          yield
        ensure
          @lock.synchronize do
            @outcome_of_the_held_initialization = outcome
            @settled.broadcast
          end
        end

        def outcome_of_the_held_initialization
          loop do
            case @outcome_of_the_held_initialization
            when :completed then return :completed
            when :failed then return :failed
            when :awaited
              remaining_seconds = @held_until_monotonic_seconds - Process.clock_gettime(Process::CLOCK_MONOTONIC)
              return outcome_at_the_timeout unless remaining_seconds.positive?

              @settled.wait(@lock, remaining_seconds)
            end
          end
        end

        private

        def hold
          @state = :holding_an_initialization
          @held_until_monotonic_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout_seconds
          @outcome_of_the_held_initialization = :awaited
        end

        def outcome_at_the_timeout
          case @state
          when :holding_an_initialization
            @state = :not_connected
            :ended_at_the_timeout
          when :connected then :completed
          when :not_connected then :failed
          end
        end

        def cancel_a_hold_of_the_next_initialization
          @next_initialization = :serves_the_values if @next_initialization == :is_held
        end
      end
    end
  end
end
