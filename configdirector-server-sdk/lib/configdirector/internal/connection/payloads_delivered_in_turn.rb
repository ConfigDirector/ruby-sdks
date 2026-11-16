# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      class PayloadsDeliveredInTurn
        def initialize
          @lock = Mutex.new
          @waiting_payloads = []
          @delivering = false
        end

        def add(payload)
          @lock.synchronize { @waiting_payloads << payload }
          nil
        end

        def deliver_each(&deliver_payload)
          loop do
            case @lock.synchronize { delivery_of_the_waiting_payloads }
            when :left_to_another_call then return nil
            when :taken_by_this_call then deliver_every_waiting_payload(&deliver_payload)
            end
          end
        end

        private

        def delivery_of_the_waiting_payloads
          return :left_to_another_call if @delivering || @waiting_payloads.empty?

          @delivering = true
          :taken_by_this_call
        end

        def deliver_every_waiting_payload
          while (payload = @lock.synchronize { @waiting_payloads.shift })
            yield payload
          end
        ensure
          @lock.synchronize { @delivering = false }
        end
      end
    end
  end
end
