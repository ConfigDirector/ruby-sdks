# frozen_string_literal: true

module Waiting
  module_function

  def wait_up_to(seconds)
    give_up_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    sleep(0.01) until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= give_up_at
  end
end
