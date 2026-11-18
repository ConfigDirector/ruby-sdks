# frozen_string_literal: true

module ConfigDirector
  module OpenFeature
    module Internal
      class Startup
        def initialize(client)
          @client = client
          @lock = Mutex.new
          @stage = :initializing
        end

        def begin_initialization
          @lock.synchronize { @stage = :initializing }
        end

        def report_due_after_initialization
          @lock.synchronize do
            if @client.ready?
              @stage = :ready
              :report_ready
            else
              @stage = :reporting_the_failure
              :report_the_failure
            end
          end
        end

        def report_due_after_the_failure
          @lock.synchronize do
            if @client.ready?
              @stage = :ready
              :report_ready
            else
              @stage = :awaiting_config
              :nothing
            end
          end
        end

        def report_due_when_config_arrives
          @lock.synchronize do
            case @stage
            when :awaiting_config
              @stage = :ready
              :report_ready
            when :initializing, :reporting_the_failure, :ready then :nothing
            end
          end
        end
      end
    end
  end
end
