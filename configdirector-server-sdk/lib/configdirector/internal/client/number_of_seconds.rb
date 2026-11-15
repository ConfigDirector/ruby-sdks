# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Client
      module NumberOfSeconds
        def self.finite?(value)
          case value
          when Integer then value.abs <= Float::MAX
          when Float then value.finite?
          else false
          end
        end

        def self.finite_and_positive?(value)
          finite?(value) && value.positive?
        end
      end
    end
  end
end
