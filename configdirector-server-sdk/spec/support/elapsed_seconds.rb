# frozen_string_literal: true

module ElapsedSeconds
  def seconds_taken
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  end
end
