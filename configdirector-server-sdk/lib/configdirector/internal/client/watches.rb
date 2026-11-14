# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class Watches
        Watch = Data.define(:config_read, :callback)

        class Watch
          def config_key
            config_read.config_key
          end

          def receive(value)
            callback.call(value)
          end
        end

        private_constant :Watch

        def initialize(log)
          @log = log
          @registrations = Registrations.new
        end

        def add(config_read, callback)
          @registrations.add(config_read.config_key, Watch.new(config_read: config_read, callback: callback))
        end

        def remove(config_key, callback)
          if callback.nil?
            @registrations.remove_all_on(config_key)
          else
            @registrations.remove_first(config_key) { |watch| watch.callback == callback }
          end
        end

        def remove_all
          @registrations.remove_all
        end

        def deliver_on(config_keys)
          @registrations.on(config_keys).each do |watch|
            value = yield watch.config_read
            @log.ignoring_errors_from("A watch on #{watch.config_key.inspect}") { watch.receive(value) }
          end
        end
      end
    end
  end
end
