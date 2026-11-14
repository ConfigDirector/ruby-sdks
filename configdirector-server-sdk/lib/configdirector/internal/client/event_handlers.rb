# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class EventHandlers
        HOOKS_BY_EVENT_NAME = {
          client_ready: ->(hooks) { hooks.client_ready },
          configs_updated: ->(hooks) { hooks.configs_updated },
          config_evaluated: ->(hooks) { hooks.config_evaluated },
          connection_error: ->(hooks) { hooks.connection_error }
        }.freeze

        HandlerRegistration = Data.define(:handler)

        private_constant :HOOKS_BY_EVENT_NAME, :HandlerRegistration

        def self.one_handler_of(handler, block)
          raise ConfigDirectorValidationError, "Give a handler or a block, not both." unless handler.nil? || block.nil?

          chosen_handler = handler.nil? ? block : handler
          return chosen_handler if chosen_handler.respond_to?(:call)

          raise ConfigDirectorValidationError,
                "Invalid handler of class #{chosen_handler.class}. Give a block or an object that responds to call."
        end

        def initialize(hooks, log)
          @log = log
          @registrations = Registrations.new
          register_the_hooks_in(hooks)
        end

        def add(event_name, handler)
          reject_an_unknown_event_name(event_name)
          register(event_name, handler)
        end

        def remove(event_name, handler)
          reject_an_unknown_event_name(event_name)
          if handler.nil?
            @registrations.remove_all_on(event_name)
          else
            @registrations.remove_first(event_name) { |registration| registration.handler == handler }
          end
        end

        def remove_all
          @registrations.remove_all
        end

        def deliver_client_ready
          deliver(:client_ready)
        end

        def deliver_configs_updated(update)
          deliver(:configs_updated, update)
        end

        def deliver_config_evaluated(evaluation)
          deliver(:config_evaluated, ConfigEvaluatedEvent.new(evaluation: evaluation))
        end

        private

        def reject_an_unknown_event_name(event_name)
          return if HOOKS_BY_EVENT_NAME.key?(event_name)

          raise ConfigDirectorValidationError,
                "Unknown event #{event_name.inspect}. " \
                "Expected one of: #{HOOKS_BY_EVENT_NAME.keys.map(&:inspect).join(", ")}."
        end

        def register(event_name, handler)
          @registrations.add(event_name, HandlerRegistration.new(handler: handler))
        end

        def register_the_hooks_in(hooks)
          HOOKS_BY_EVENT_NAME.each do |event_name, hooks_of_the_event|
            handlers_given(hooks_of_the_event.call(hooks)).each { |handler| register_a_hook(event_name, handler) }
          end
        end

        def register_a_hook(event_name, handler)
          return register(event_name, handler) if handler.respond_to?(:call)

          @log.warn(
            "A #{event_name.inspect} hook of class #{handler.class} was ignored because it does not respond to call."
          )
        end

        def handlers_given(hooks_of_the_event)
          case hooks_of_the_event
          when nil then []
          when Array then hooks_of_the_event
          else [hooks_of_the_event]
          end
        end

        def deliver(event_name, *arguments)
          @registrations.on([event_name]).each do |registration|
            @log.ignoring_errors_from("A handler for the event #{event_name.inspect}") do
              registration.handler.call(*arguments)
            end
          end
        end
      end
    end
  end
end
