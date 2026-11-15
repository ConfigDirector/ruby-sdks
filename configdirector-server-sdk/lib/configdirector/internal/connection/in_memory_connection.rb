# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      class InMemoryConnection
        REFUSAL_MESSAGE = "Connection failed with status: 401. Error: the test client failed this initialization. " \
                          "This is an unrecoverable error, will not attempt to reconnect."

        private_constant :REFUSAL_MESSAGE

        def initialize(values, timeout_seconds:, logger:)
          @values = TestClientValues.serving(values || {})
          @log = Logging::ClientLog.new(logger, component: "InMemoryConnection")
          @lock = Mutex.new
          @initializations = TestClientInitializations.new(@lock, timeout_seconds)
          @payloads_delivered_in_turn = PayloadsDeliveredInTurn.new
          @deliver_payload = ->(_payload) {}
          @report_unrecoverable_error = ->(_connection_error) {}
        end

        def set_value(config_key, value)
          values_set = TestClientValues.serving({ config_key => value })
          @lock.synchronize do
            @values = @values.merged_with(values_set)
            add_if_connected(values_set.delta_payload)
          end
          deliver_the_waiting_payloads
        end

        def remove_value(given_key)
          @lock.synchronize do
            @values = @values.without_the_value_of(given_key)
            add_if_connected(@values.full_payload)
          end
          deliver_the_waiting_payloads
        end

        def replace_values(values)
          replacing_values = TestClientValues.serving(values)
          @lock.synchronize do
            @values = replacing_values
            @initializations.serve_the_values_at_the_next_initialization
            add_if_connected(@values.full_payload)
          end
          deliver_the_waiting_payloads
        end

        def hold_initialization
          @lock.synchronize { @initializations.hold_the_next_initialization }
        end

        def complete_initialization
          case @lock.synchronize { @initializations.complete_initialization }
          when :held_initialization_completed then deliver_the_values_to_the_held_initialization
          when :no_initialization_held then nil
          end
        end

        def fail_initialization
          case @lock.synchronize { @initializations.fail_initialization }
          when :held_initialization_failed
            @initializations.settling_the_held_initialization(:failed) { report_the_refusal }
          when :next_initialization_fails then nil
          end
          nil
        end

        def open(report_unrecoverable_error:, &deliver_payload)
          @report_unrecoverable_error = report_unrecoverable_error
          @deliver_payload = deliver_payload

          case @lock.synchronize { begin_the_next_initialization }
          when :serves_the_values then deliver_the_stored_values
          when :fails then refuse_the_initialization
          when :is_held then what_follows_the_held_initialization
          end
        end

        def restart_in_a_forked_process(**); end

        def close; end

        private

        def begin_the_next_initialization
          next_initialization = @initializations.begin_the_next_initialization
          add_if_connected(@values.full_payload)

          next_initialization
        end

        def deliver_the_stored_values
          deliver_the_waiting_payloads

          :values_awaited
        end

        def refuse_the_initialization
          report_the_refusal

          :first_attempt_failed
        end

        def what_follows_the_held_initialization
          case @lock.synchronize { @initializations.outcome_of_the_held_initialization }
          when :completed, :ended_at_the_timeout then :values_awaited
          when :failed then :first_attempt_failed
          end
        end

        def deliver_the_values_to_the_held_initialization
          @initializations.settling_the_held_initialization(:completed) do
            @lock.synchronize { @payloads_delivered_in_turn.add(@values.full_payload) }
            deliver_the_waiting_payloads
          end
        end

        def report_the_refusal
          @log.error(REFUSAL_MESSAGE)
          @report_unrecoverable_error.call(ConfigDirectorConnectionError.new(REFUSAL_MESSAGE, status: 401))
        end

        def add_if_connected(payload)
          @payloads_delivered_in_turn.add(payload) if @initializations.connected?
        end

        def deliver_the_waiting_payloads
          @payloads_delivered_in_turn.deliver_each(&@deliver_payload)
        end
      end
    end
  end
end
