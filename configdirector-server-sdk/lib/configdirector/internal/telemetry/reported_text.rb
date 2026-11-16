# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Telemetry
      module ReportedText
        def self.of(text)
          Value::Utf8Text.of(text) || String.new(text, encoding: Encoding::UTF_8).scrub
        end
      end
    end
  end
end
