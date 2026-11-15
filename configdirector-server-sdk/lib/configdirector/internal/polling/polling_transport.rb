# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Polling
      class PollingTransport
        SECONDS_CLOSE_WAITS_FOR_THE_THREAD = 5

        private_constant :SECONDS_CLOSE_WAITS_FOR_THE_THREAD

        def initialize(endpoint:, timing:, logger:)
          @session = PollingSession.new(
            endpoint: endpoint, timing: timing, log: Logging::ClientLog.new(logger, component: "PollingTransport")
          )
          @lock = Mutex.new
          @closed = false
          @polling_thread = nil
        end

        def open(report_unrecoverable_error:, &deliver_payload_text)
          what_follows_the_first_poll = @session.poll(report_unrecoverable_error, deliver_payload_text)
          unless what_follows_the_first_poll == :end_of_polling
            poll_on_every_interval_unless_closed(report_unrecoverable_error, deliver_payload_text)
          end

          what_follows_the_first_poll
        end

        def restart_in_a_forked_process(report_unrecoverable_error:, &deliver_payload_text)
          @session = @session.session_of_a_forked_process
          start_the_polling_thread_unless_closed do
            @session.poll_at_once_and_on_every_interval(report_unrecoverable_error, deliver_payload_text)
          end
        end

        def close
          polling_thread = @lock.synchronize do
            @closed = true
            @polling_thread
          end
          return if polling_thread.nil?

          polling_thread.stop
          polling_thread.join_within(SECONDS_CLOSE_WAITS_FOR_THE_THREAD)
        end

        private

        def poll_on_every_interval_unless_closed(report_unrecoverable_error, deliver_payload_text)
          start_the_polling_thread_unless_closed do
            @session.poll_on_every_interval(report_unrecoverable_error, deliver_payload_text)
          end
        end

        def start_the_polling_thread_unless_closed(&polling)
          @lock.synchronize do
            return if @closed

            @polling_thread = StoppableThread.start("configdirector-polling", &polling)
          end
        end
      end
    end
  end
end
