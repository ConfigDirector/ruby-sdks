# frozen_string_literal: true

require "weakref"
require_relative "recording_logger"

module GarbageCollection
  # Ruby scans thread stacks conservatively, so a stale word on a stack can keep a logger alive through every later
  # collection. A logger the SDK held would survive with every client, so one collected logger in three is the proof.
  CLIENTS_TRIED = 3

  def logger_collected_once_the_client_is_unreferenced?(&create_a_client_with)
    CLIENTS_TRIED.times.any? do
      weak_logger = Thread.new do
        logger_of_the_client = RecordingLogger.new
        create_a_client_with.call(logger_of_the_client)

        WeakRef.new(logger_of_the_client)
      end.value

      GC.start

      !weak_logger.weakref_alive?
    end
  end
end
