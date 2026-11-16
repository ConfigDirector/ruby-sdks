# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class LiveClientConnections
        def initialize
          @lock = Mutex.new
          @client_connections = []
        end

        def add(client_connection)
          @lock.synchronize { @client_connections = without(client_connection) + [client_connection] }
          nil
        end

        def remove(client_connection)
          @lock.synchronize { @client_connections = without(client_connection) }
          nil
        end

        def restart_in_a_forked_process(forked_through)
          client_connections = @client_connections
          return if client_connections.empty?

          client_connections.each do |client_connection|
            client_connection.choose_the_reporter_of_what_the_parent_process_collected(forked_through)
          end
          restart_each_on_a_thread_of_the_forked_process(client_connections)
        end

        OF_THE_PROCESS = new

        private

        def without(client_connection)
          @client_connections.reject { |added| added.equal?(client_connection) }
        end

        def restart_each_on_a_thread_of_the_forked_process(client_connections)
          Thread.new { restart_each_in_a_forked_process(client_connections) }
          nil
        rescue ThreadError
          restart_each_in_a_forked_process(client_connections)
        end

        def restart_each_in_a_forked_process(client_connections)
          client_connections.each do |client_connection|
            client_connection.restart_in_a_forked_process
          rescue StandardError
            nil
          end
          nil
        end
      end
    end
  end
end
