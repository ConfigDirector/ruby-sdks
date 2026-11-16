# frozen_string_literal: true

require "logger"

module ConfigDirector
  module Internal
    module Logging
      module DefaultLogger
        LINE_PREFIX = "[ConfigDirector:ruby-server-sdk]"
        LINE_FORMAT = ->(severity, _time, _program_name, message) { "#{LINE_PREFIX} #{severity}: #{message}\n" }.freeze
        LOGGER_LEVELS = (Logger::DEBUG..Logger::UNKNOWN)

        def self.writing_from(log_level)
          lowest_level_written = log_level.nil? ? Logger::WARN : log_level
          raise invalid(log_level) if lowest_level_written.is_a?(Integer) && !LOGGER_LEVELS.cover?(lowest_level_written)

          Logger.new($stderr, level: lowest_level_written, formatter: LINE_FORMAT)
        rescue ArgumentError
          raise invalid(log_level)
        end

        def self.invalid(log_level)
          ConfigDirectorValidationError.new(
            "Invalid log level #{log_level.inspect}. The log level must be one that Ruby's Logger takes, " \
            "such as :debug, :info, :warn or :error."
          )
        end

        private_constant :LINE_PREFIX, :LINE_FORMAT, :LOGGER_LEVELS
        private_class_method :invalid
      end
    end
  end
end
