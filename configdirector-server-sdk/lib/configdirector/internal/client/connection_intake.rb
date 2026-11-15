# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class ConnectionIntake
        def initialize(serving_state:, event_handlers:, watches:, config_reader:, log:)
          @serving_state = serving_state
          @event_handlers = event_handlers
          @watches = watches
          @config_reader = config_reader
          @log = log
        end

        def take_in(payload)
          warn_of_the_definitions_skipped_in(payload)
          arrival, update = @serving_state.serve(payload)

          case arrival
          when :after_close then nil
          when :newer_values then deliver_the_update(update)
          when :first_values then deliver_the_first_values(update)
          end
        end

        def take_in_unrecoverable_error(connection_error)
          @serving_state.expect_no_values_from_the_connection
          @event_handlers.deliver_connection_error(connection_error)
        end

        private

        def warn_of_the_definitions_skipped_in(payload)
          payload.unreadable_configs.each do |config_key, cause|
            @log.warn("Skipping the config '#{config_key}', its definition could not be read: #{cause}")
          end
          payload.unreadable_segments.each do |segment_id, cause|
            @log.warn("Skipping the segment '#{segment_id}', its definition could not be read: #{cause}")
          end
        end

        def deliver_the_first_values(update)
          deliver_the_update(update)
          @event_handlers.deliver_client_ready
          @log.debug { "Received initial payload from the server, client is ready" }
        ensure
          @serving_state.end_the_delivery_of_the_first_values
        end

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
