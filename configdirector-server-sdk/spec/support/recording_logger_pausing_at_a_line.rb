# frozen_string_literal: true

require_relative "recording_logger"

class RecordingLoggerPausingAtALine < RecordingLogger
  attr_reader :pauses_begun

  def initialize(text_of_the_line, seconds_paused)
    super()
    @text_of_the_line = text_of_the_line
    @seconds_paused = seconds_paused
    @pauses_begun = Queue.new
  end

  def debug(message)
    super
    return unless message.include?(@text_of_the_line)

    @pauses_begun << message
    sleep(@seconds_paused)
  end
end
