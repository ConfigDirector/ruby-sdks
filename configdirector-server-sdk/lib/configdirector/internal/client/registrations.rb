# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      class Registrations
        def initialize
          @lock = Mutex.new
          @registrations_by_topic = {}
        end

        def add(topic, registration)
          @lock.synchronize { (@registrations_by_topic[topic] ||= []) << registration }
          Subscription.new { remove_first(topic) { |registered| registered.equal?(registration) } }
        end

        def remove_first(topic, &matches)
          @lock.synchronize do
            registrations = @registrations_by_topic.fetch(topic, [])
            position = registrations.index(&matches)
            registrations.delete_at(position) unless position.nil?
            @registrations_by_topic.delete(topic) if registrations.empty?
          end
          nil
        end

        def remove_all_on(topic)
          @lock.synchronize { @registrations_by_topic.delete(topic) }
          nil
        end

        def remove_all
          @lock.synchronize { @registrations_by_topic.clear }
          nil
        end

        def on(topics)
          @lock.synchronize { topics.flat_map { |topic| @registrations_by_topic.fetch(topic, []).dup } }
        end
      end
    end
  end
end
