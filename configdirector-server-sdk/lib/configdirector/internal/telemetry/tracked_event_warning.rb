# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      module TrackedEventWarning
        MESSAGE_BY_WARNING = {
          name_outside_the_character_limit: "A tracked event was not reported because its name does not have 1 to " \
                                            "#{TrackedEventAdmission::NAME_MAXIMUM_CHARACTERS} characters.",
          value_not_a_finite_number: "A tracked event was reported without its value because the value is not a " \
                                     "finite number.",
          details_not_reportable: "A tracked event was reported without its details because they are not an " \
                                  "object, have more than #{ReportedDetails::MOST_TOP_LEVEL_KEYS} top-level keys, " \
                                  "are larger than #{ReportedDetails::MOST_JSON_BYTES} bytes as JSON, or cannot be " \
                                  "written as JSON.",
          batch_already_full: "A tracked event was not reported because #{TrackedEventQueue::EVENTS_PER_REPORT} " \
                              "tracked events are already waiting for the next telemetry batch."
        }.freeze

        private_constant :MESSAGE_BY_WARNING

        def self.message_of(warning)
          MESSAGE_BY_WARNING.fetch(warning)
        end
      end
    end
  end
end
