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
          @lock.synchronize { @client_connections << client_connection }
          nil
        end

        def remove(client_connection)
          @lock.synchronize { @client_connections.delete_if { |added| added.equal?(client_connection) } }
          nil
        end

        def restart_in_a_forked_process
          return if @client_connections.empty?

          Thread.new { restart_each_in_a_forked_process }.join
          nil
        rescue ThreadError
          restart_each_in_a_forked_process
        end

        OF_THE_PROCESS = new

        private

        def restart_each_in_a_forked_process
          @lock.synchronize { @client_connections.dup }.each do |client_connection|
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
