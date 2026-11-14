# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Logging
      class ClientLog
        def initialize(logger, component: "ConfigDirectorClient")
          @logger = logger
          @line_prefix = "[#{component}]"
          @writes_debug_lines = logger.respond_to?(:debug?) ? logger.method(:debug?) : -> { true }
        end

        def debug
          @logger.debug("#{@line_prefix} #{yield}") if @writes_debug_lines.call
        end

        def info(line)
          @logger.info("#{@line_prefix} #{line}")
        end

        def warn(line)
          @logger.warn("#{@line_prefix} #{line}")
        end

        def error(line)
          @logger.error("#{@line_prefix} #{line}")
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
