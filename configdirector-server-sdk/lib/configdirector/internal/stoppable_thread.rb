# frozen_string_literal: true

module ConfigDirector
  module Internal
    class StoppableThread
      class Stopped < Exception; end

      ID_OF_THE_PROCESS_THAT_STARTED_THE_THREAD = :configdirector_id_of_the_process_that_started_the_thread
      ASKED_ITSELF_TO_STOP = :configdirector_thread_asked_itself_to_stop

      private_constant :Stopped, :ID_OF_THE_PROCESS_THAT_STARTED_THE_THREAD, :ASKED_ITSELF_TO_STOP

      def self.start(name, &work)
        thread = Thread.handle_interrupt(Stopped => :never) do
          Thread.new do
            Thread.current.thread_variable_set(ID_OF_THE_PROCESS_THAT_STARTED_THE_THREAD, Process.pid)
            work.call
          rescue Stopped
            nil
          end
        end
        thread.name = name
        new(thread)
      end

      def self.stoppable(&blocking_call)
        stop_here_when_the_thread_must_end
        Thread.handle_interrupt(Stopped => :on_blocking) { blocking_call.call }
      end

      def self.unstoppable(&work)
        Thread.handle_interrupt(Stopped => :never) { work.call }
      end

      def self.stop_here_if_asked_to
        stop_here_when_the_thread_must_end
        Thread.handle_interrupt(Stopped => :immediate) { Thread.pass }
      end

      def self.stop_here_when_the_thread_must_end
        raise Stopped if copied_by_a_forked_process? || Thread.current.thread_variable_get(ASKED_ITSELF_TO_STOP)
      end

      def self.copied_by_a_forked_process?
        id_of_the_starting_process = Thread.current.thread_variable_get(ID_OF_THE_PROCESS_THAT_STARTED_THE_THREAD)

        !id_of_the_starting_process.nil? && id_of_the_starting_process != Process.pid
      end

      private_class_method :stop_here_when_the_thread_must_end, :copied_by_a_forked_process?

      def initialize(thread)
        @thread = thread
      end

      def stop
        if @thread.equal?(Thread.current)
          @thread.thread_variable_set(ASKED_ITSELF_TO_STOP, true)
        else
          @thread.raise(Stopped)
        end
      end

      def join_within(seconds)
        @thread.join(seconds) unless @thread.equal?(Thread.current)
      end
    end
  end
end
