# frozen_string_literal: true

require_relative "recording_logger"

class RecordingLoggerWritingUnderALock < RecordingLogger
  def initialize
    super
    @lock = Mutex.new
    @signal_sent_while_the_lock_is_held = nil
  end

  def send_once_while_the_lock_is_held(signal)
    @signal_sent_while_the_lock_is_held = signal
  end

  def debug(message)
    @lock.synchronize do
      super
      send_the_signal_and_wait_for_its_handler
    end
  end

  private

  def send_the_signal_and_wait_for_its_handler
    signal = @signal_sent_while_the_lock_is_held
    return if signal.nil?

    @signal_sent_while_the_lock_is_held = nil
    Process.kill(signal, Process.pid)
    sleep(0.2)
  end
end
