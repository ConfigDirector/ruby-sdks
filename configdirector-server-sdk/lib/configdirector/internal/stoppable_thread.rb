# frozen_string_literal: true

module ConfigDirector
  module Internal
    class StoppableThread
      class Stopped < Exception; end

      private_constant :Stopped

      def self.start(name, &work)
        thread = Thread.handle_interrupt(Stopped => :never) do
          Thread.new do
            work.call
          rescue Stopped
            nil
          end
        end
        thread.name = name
        new(thread)
      end

      def self.stoppable(&blocking_call)
        Thread.handle_interrupt(Stopped => :on_blocking) { blocking_call.call }
      end

      def self.unstoppable(&work)
        Thread.handle_interrupt(Stopped => :never) { work.call }
      end

      def self.stop_here_if_asked_to
        Thread.handle_interrupt(Stopped => :immediate) { Thread.pass }
      end

      def initialize(thread)
        @thread = thread
      end

      def stop
        @thread.raise(Stopped)
      end

      def join_within(seconds)
        @thread.join(seconds) unless @thread.equal?(Thread.current)
      end
    end
  end
end
