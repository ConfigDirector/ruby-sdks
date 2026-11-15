# frozen_string_literal: true

module SdkThreads
  def sdk_threads_alive
    Thread.list.select { |thread| thread.alive? && thread.name.to_s.start_with?("configdirector-") }
  end

  def wait_until_no_sdk_thread_is_alive
    give_up_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    sleep(0.01) while sdk_threads_alive.any? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < give_up_at
  end
end
