# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      AdmittedTrackedEvent = Data.define(:entry, :context, :warnings)
      DroppedTrackedEvent = Data.define(:warnings)

      module TrackedEventAdmission
        NAME_MAXIMUM_CHARACTERS = 150

        ReportedPart = Data.define(:reported, :warnings)

        class ReportedPart
          def self.not_given
            new(reported: nil, warnings: [])
          end

          def self.of(reported)
            new(reported: reported, warnings: [])
          end

          def self.left_out_with(warning)
            new(reported: nil, warnings: [warning])
          end
        end

        private_constant :ReportedPart

        def self.of(name:, context:, value:, details:, happened_at:)
          reported_name = reported_name_of(name)
          return DroppedTrackedEvent.new(warnings: [:name_outside_the_character_limit]) if reported_name.nil?

          value_part = reported_value_of(value)
          details_part = reported_details_of(details)
          entry = TrackedEventEntry.of(
            name: reported_name, context: context, value: value_part.reported, details: details_part.reported,
            happened_at: happened_at
          )
          warnings = value_part.warnings + details_part.warnings
          AdmittedTrackedEvent.new(entry: entry, context: context, warnings: warnings)
        end

        def self.reported_name_of(name)
          return nil unless name.is_a?(String) || name.is_a?(Symbol)

          name_text = ReportedText.of(name.to_s)
          name_text if name_text.length.between?(1, NAME_MAXIMUM_CHARACTERS)
        end

        def self.reported_value_of(value)
          if value.nil?
            ReportedPart.not_given
          elsif (value.is_a?(Integer) || value.is_a?(Float)) && CompactJsonText.number_javascript_holds?(value)
            ReportedPart.of(value)
          else
            ReportedPart.left_out_with(:value_not_a_finite_number)
          end
        end

        def self.reported_details_of(details)
          return ReportedPart.not_given if details.nil?

          written_details = ReportedDetails.json_of(details)
          written_details.nil? ? ReportedPart.left_out_with(:details_not_reportable) : ReportedPart.of(written_details)
        end

        private_class_method :reported_name_of, :reported_value_of, :reported_details_of
      end
    end
  end
end
