# frozen_string_literal: true

module SpawnedProcess
  def exit_status_within(seconds, process_id)
    give_up_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < give_up_at
      _process_id, exit_status = Process.wait2(process_id, Process::WNOHANG)
      return exit_status unless exit_status.nil?

      sleep(0.05)
    end
    Process.kill("KILL", process_id)
    Process.wait(process_id)
    nil
  end
end
