# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class ClientConnection
        CONNECTION_AT_A_LATER_INIT_BY_MODE = {
          "streaming" => :left_open,
          "polling" => :left_open,
          "offline" => :opened_again,
          "test" => :opened_again
        }.freeze

        WHAT_FOLLOWS_AN_INIT_WITHOUT_VALUES_BY_MODE = {
          "streaming" => "The client will continue to retry since there were no fatal errors detected. " \
                         "Configs will return the in-code default value until the connection succeeds.",
          "polling" => "Since the client was configured without streaming, configs may not update and always " \
                       "return the in-code default value.",
          "offline" => "The offline values were not delivered, so configs return the in-code default value.",
          "test" => "Configs return the in-code default value until values arrive."
        }.freeze

        private_constant :CONNECTION_AT_A_LATER_INIT_BY_MODE, :WHAT_FOLLOWS_AN_INIT_WITHOUT_VALUES_BY_MODE

        def initialize(connection:, telemetry:, mode:, serving_state:, intake:, log:)
          @connection = connection
          @telemetry = telemetry
          @mode = mode
          @connection_opened = false
          @serving_state = serving_state
          @log = log
          @report_unrecoverable_error = ->(connection_error) { intake.take_in_unrecoverable_error(connection_error) }
          @deliver_payload = ->(payload) { intake.take_in(payload) }
        end

        def open
          @telemetry.start_reporting
          case connection_at_this_init
          when :left_open then :opened_before
          when :opened_for_the_first_time, :opened_again then open_the_connection
          end
        end

        def close
          LiveClientConnections::OF_THE_PROCESS.remove(self)
          @connection.close
          @telemetry.close
        end

        def warn_that_no_values_arrived_within(timeout)
          @log.warn(
            "Timed out waiting for initialization after #{format("%g", timeout)}s. " \
            "#{WHAT_FOLLOWS_AN_INIT_WITHOUT_VALUES_BY_MODE.fetch(@mode)}"
          )
        end

        def restart_in_a_forked_process(forked_through)
          case what_follows_a_fork
          when :nothing_to_restart then nil
          when :restart_the_connection
            restart_the_telemetry(forked_through)
            restart_the_connection
          end
        rescue StandardError => e
          @log.error(
            "Failed to restart the connection in forked process #{Process.pid}: #{e.class}: #{e.message.inspect}"
          )
        end

        private

        def connection_at_this_init
          return :opened_for_the_first_time unless @connection_opened

          CONNECTION_AT_A_LATER_INIT_BY_MODE.fetch(@mode)
        end

        def open_the_connection
          @connection_opened = true
          @serving_state.expect_values_from_the_connection
          Process.singleton_class.prepend(RestartInForkedProcesses)
          case what_follows_a_fork
          when :nothing_to_restart then nil
          when :restart_the_connection then LiveClientConnections::OF_THE_PROCESS.add(self)
          end

          @connection.open(report_unrecoverable_error: @report_unrecoverable_error, &@deliver_payload)
        end

        def what_follows_a_fork
          WhatFollowsAFork.for_a_client_with(
            mode: @mode, closed: @serving_state.closed?,
            connection_failed_unrecoverably: @serving_state.connection_failed_unrecoverably?
          )
        end

        def restart_the_telemetry(forked_through)
          @telemetry.restart_in_a_forked_process(forked_through)
        rescue StandardError => e
          @log.error("Failed to restart telemetry in forked process #{Process.pid}: #{e.class}: #{e.message.inspect}")
        end

        def restart_the_connection
          @log.debug { "Restarting the connection in forked process #{Process.pid}" }
          @serving_state.leave_the_delivery_of_the_first_values_to_the_parent_process
          @connection.restart_in_a_forked_process(
            report_unrecoverable_error: @report_unrecoverable_error, &@deliver_payload
          )
        end
      end
    end
  end
end
