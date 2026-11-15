# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      module RestartInForkedProcesses
        if Process.respond_to?(:_fork)
          def _fork
            process_id = super
            LiveClientConnections::OF_THE_PROCESS.restart_in_a_forked_process if process_id.zero?
            process_id
          end
        end

        if Process.respond_to?(:daemon)
          def daemon(*)
            result = super
            LiveClientConnections::OF_THE_PROCESS.restart_in_a_forked_process
            result
          end
        end
      end
    end
  end
end
