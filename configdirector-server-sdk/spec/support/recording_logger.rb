# frozen_string_literal: true

class RecordingLogger
  def initialize
    @lines = Queue.new
  end

  def debug(message)
    @lines << [:debug, message]
  end

  def info(message)
    @lines << [:info, message]
  end

  def warn(message)
    @lines << [:warn, message]
  end

  def error(message)
    @lines << [:error, message]
  end

  def messages_at(severity)
    lines = []
    lines << @lines.pop until @lines.empty?
    lines.each { |line| @lines << line }

    lines.select { |line_severity, _message| line_severity == severity }.map(&:last)
  end
end
