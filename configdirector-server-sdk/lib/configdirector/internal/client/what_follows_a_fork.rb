# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      module WhatFollowsAFork
        WHAT_FOLLOWS_A_FORK_BY_MODE = {
          "streaming" => :restart_the_connection,
          "polling" => :restart_the_connection,
          "offline" => :nothing_to_restart,
          "test" => :nothing_to_restart
        }.freeze

        private_constant :WHAT_FOLLOWS_A_FORK_BY_MODE

        def self.for_a_client_with(mode:, closed:, connection_failed_unrecoverably:)
          return :nothing_to_restart if closed || connection_failed_unrecoverably

          WHAT_FOLLOWS_A_FORK_BY_MODE.fetch(mode)
        end
      end
    end
  end
end
