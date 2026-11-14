# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      module DatetimeComparison
        ECMASCRIPT_DATE_TIME = /
          \A(?<year>[+-][0-9]{6}|[0-9]{4})
          (?:-(?<month>[0-9]{2})(?:-(?<day>[0-9]{2}))?)?
          (?:T(?<hour>[0-9]{2}):(?<minute>[0-9]{2})(?::(?<second>[0-9]{2})(?:\.(?<fraction>[0-9]+))?)?
          (?<offset>[Zz]|[+-][0-9]{2}:[0-9]{2})?)?\z
        /x

        DAYS_IN_MONTH_OF_A_COMMON_YEAR = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze

        def self.matches?(text, operator, targets)
          instant = milliseconds_since_epoch_of(text)
          target = targets.empty? ? nil : milliseconds_since_epoch_of(targets.first)
          return false if instant.nil? || target.nil?

          case operator
          when "is before" then instant < target
          when "is after" then instant > target
          else false
          end
        end

        def self.milliseconds_since_epoch_of(text)
          match = ECMASCRIPT_DATE_TIME.match(text)
          return nil if match.nil?

          calendar_fields = possible_calendar_fields_of(match)
          offset_minutes = offset_minutes_of(match[:offset])
          return nil if calendar_fields.nil? || offset_minutes.nil?

          milliseconds_read_as_utc(calendar_fields, match[:fraction]) - (offset_minutes * 60_000)
        end

        def self.possible_calendar_fields_of(match)
          year = match[:year].to_i
          month = match[:month]&.to_i || 1
          day = match[:day]&.to_i || 1
          hour = match[:hour].to_i
          minute = match[:minute].to_i
          second = match[:second].to_i
          return nil unless possible_date?(year, month, day) && possible_time?(hour, minute, second)

          [year, month, day, hour, minute, second]
        end

        def self.milliseconds_read_as_utc(calendar_fields, fraction)
          year, month, day, hour, minute, second = calendar_fields
          millisecond = fraction.to_s[0, 3].to_s.ljust(3, "0").to_i

          (Time.utc(year, month, day, hour, minute, second).to_i * 1000) + millisecond
        end

        def self.offset_minutes_of(offset)
          return 0 if offset.nil? || offset == "Z" || offset == "z"

          hours = offset[1, 2].to_i
          minutes = offset[4, 2].to_i
          return nil unless possible_time?(hours, minutes, 0)

          (offset.start_with?("-") ? -1 : 1) * ((hours * 60) + minutes)
        end

        def self.possible_date?(year, month, day)
          month.between?(1, 12) && day.between?(1, days_in_month(year, month))
        end

        def self.possible_time?(hour, minute, second)
          hour <= 23 && minute <= 59 && second <= 59
        end

        def self.days_in_month(year, month)
          return 29 if month == 2 && leap_year?(year)

          DAYS_IN_MONTH_OF_A_COMMON_YEAR.fetch(month - 1)
        end

        def self.leap_year?(year)
          (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)
        end

        private_constant :ECMASCRIPT_DATE_TIME, :DAYS_IN_MONTH_OF_A_COMMON_YEAR
        private_class_method :milliseconds_since_epoch_of, :possible_calendar_fields_of, :milliseconds_read_as_utc,
                             :offset_minutes_of,
                             :possible_date?, :possible_time?, :days_in_month, :leap_year?
      end
    end
  end
end
