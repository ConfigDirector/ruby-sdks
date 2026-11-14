# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Logging
      class ClientLog
        LINE_PREFIX = "[ConfigDirectorClient]"

        private_constant :LINE_PREFIX

        def initialize(logger)
          @logger = logger
          @writes_debug_lines = logger.respond_to?(:debug?) ? logger.method(:debug?) : -> { true }
        end

        def debug
          @logger.debug("#{LINE_PREFIX} #{yield}") if @writes_debug_lines.call
        end

        def warn(line)
          @logger.warn("#{LINE_PREFIX} #{line}")
        end

        def error(line)
          @logger.error("#{LINE_PREFIX} #{line}")
        end

        def ignoring_errors_from(source)
          yield
        rescue StandardError => e
          error("#{source} raised an error, which was ignored: #{e.class}: #{e.message.inspect}")
        end
      end
    end
  end
end
