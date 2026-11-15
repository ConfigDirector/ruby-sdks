# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class ServingState
        def initialize(metadata)
          @metadata = metadata
          @lock = Mutex.new
          @first_values_no_longer_awaited = ConditionVariable.new
          @served_configs = nil
          @thread_delivering_the_first_values = nil
          @first_values_delivered = false
          @closed = false
          @connection_failed_unrecoverably = false
        end

        def served_configs
          @lock.synchronize { @served_configs }
        end

        def closed?
          @lock.synchronize { @closed }
        end

        def connection_failed_unrecoverably?
          @lock.synchronize { @connection_failed_unrecoverably }
        end

        def serve(payload)
          @lock.synchronize do
            arrival = arrival_of_values
            replaced_configs = @served_configs || ServedConfigs.without_definitions(@metadata)
            served_configs = replaced_configs.after(payload)
            update = served_configs.update_since(replaced_configs, payload)
            @served_configs = served_configs unless arrival == :after_close
            @thread_delivering_the_first_values = Thread.current if arrival == :first_values

            [arrival, update]
          end
        end

        def end_the_delivery_of_the_first_values
          @lock.synchronize do
            @first_values_delivered = true
            @thread_delivering_the_first_values = nil
            @first_values_no_longer_awaited.broadcast
          end
        end

        def close
          @lock.synchronize do
            @closed = true
            @served_configs = nil
            @first_values_no_longer_awaited.broadcast
          end
        end

        def expect_values_from_the_connection
          @lock.synchronize { @connection_failed_unrecoverably = false }
        end

        def expect_no_values_from_the_connection
          @lock.synchronize do
            @connection_failed_unrecoverably = true
            @first_values_no_longer_awaited.broadcast
          end
        end

        def leave_the_delivery_of_the_first_values_to_the_parent_process
          @lock.synchronize { @first_values_delivered = true unless @served_configs.nil? }
        end

        def timed_out_waiting_for_the_first_values?(give_up_at_monotonic_seconds)
          @lock.synchronize do
            loop do
              return false if @closed || @connection_failed_unrecoverably
              return false if @first_values_delivered || @thread_delivering_the_first_values.equal?(Thread.current)

              remaining_seconds = give_up_at_monotonic_seconds - Process.clock_gettime(Process::CLOCK_MONOTONIC)
              return @served_configs.nil? unless remaining_seconds.positive?

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
