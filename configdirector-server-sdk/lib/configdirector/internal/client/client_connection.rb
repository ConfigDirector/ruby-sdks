# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class ClientConnection
        CONNECTION_AT_A_LATER_INIT_BY_MODE = {
          "streaming" => :left_open,
          "polling" => :left_open,
          "offline" => :opened_again
        }.freeze

        private_constant :CONNECTION_AT_A_LATER_INIT_BY_MODE

        def initialize(connection:, mode:, serving_state:, intake:, log:)
          @connection = connection
          @mode = mode
          @connection_opened = false
          @serving_state = serving_state
          @log = log
          @report_unrecoverable_error = ->(connection_error) { intake.take_in_unrecoverable_error(connection_error) }
          @deliver_payload = ->(payload) { intake.take_in(payload) }
        end

        def open
          case connection_at_this_init
          when :left_open then :opened_before
          when :opened_for_the_first_time, :opened_again then open_the_connection
          end
        end

        def close
          LiveClientConnections::OF_THE_PROCESS.remove(self)
          @connection.close
        end

        def restart_in_a_forked_process
          case what_follows_a_fork
          when :nothing_to_restart then nil
          when :restart_the_connection then restart_the_connection
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
