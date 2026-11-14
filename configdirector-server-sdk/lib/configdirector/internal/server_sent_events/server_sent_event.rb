# frozen_string_literal: true

module ConfigDirector
  module Internal
    module ServerSentEvents
      ServerSentEvent = Data.define(:type, :data)
    end
  end
end
