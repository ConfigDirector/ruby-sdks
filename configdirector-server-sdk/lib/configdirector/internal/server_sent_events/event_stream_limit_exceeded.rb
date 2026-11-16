# frozen_string_literal: true

module ConfigDirector
  module Internal
    module ServerSentEvents
      class EventStreamLimitExceeded < ConfigDirectorError; end
    end
  end
end
