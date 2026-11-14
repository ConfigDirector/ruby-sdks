# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class ConnectionIntake
        def initialize(metadata:, serving_state:, event_handlers:, watches:, config_reader:, log:)
          @metadata = metadata
          @serving_state = serving_state
          @event_handlers = event_handlers
          @watches = watches
          @config_reader = config_reader
          @log = log
        end

        def take_in(payload)
          served_configs = ServedConfigs.new(payload: payload, metadata: @metadata)
          arrival, replaced_configs = @serving_state.serve(served_configs)

          case arrival
          when :after_close then nil
          when :newer_values then deliver_the_update(served_configs.update_since(replaced_configs))
          when :first_values
            deliver_the_update(served_configs.update_since(replaced_configs))
            @event_handlers.deliver_client_ready
            @log.debug { "Received initial payload from the server, client is ready" }
          end
        end

        def take_in_unrecoverable_error(connection_error)
          @serving_state.expect_no_values_from_the_connection
          @event_handlers.deliver_connection_error(connection_error)
        end

        private

        def deliver_the_update(update)
          @event_handlers.deliver_configs_updated(update)
          @watches.deliver_on(update.keys + update.removed_keys) do |config_read|
            @config_reader.read(config_read).value
          end
        end
      end
    end
  end
end
