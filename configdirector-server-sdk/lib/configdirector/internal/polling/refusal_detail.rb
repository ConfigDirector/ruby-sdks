# frozen_string_literal: true

require "json"

module ConfigDirector
  module Internal
    module Polling
      module RefusalDetail
        MAXIMUM_BYTES = 1_024

        private_constant :MAXIMUM_BYTES

        def self.of(answer_body, server_sdk_key_to_hide:)
          detail = written_forms_of(server_sdk_key_to_hide).reduce(answer_body) do |text, written_form|
            text.gsub(written_form, "[the server SDK key]")
          end.strip
          return detail unless detail.bytesize > MAXIMUM_BYTES

          "#{detail.byteslice(0, MAXIMUM_BYTES).to_s.scrub("").strip}…"
        end

        def self.written_forms_of(server_sdk_key)
          key_without_the_space_around_it = server_sdk_key.strip
          [
            server_sdk_key,
            key_without_the_space_around_it,
            JSON.generate(key_without_the_space_around_it)[1...-1].to_s,
            JSON.generate(key_without_the_space_around_it, script_safe: true)[1...-1].to_s
          ]
        end

        private_class_method :written_forms_of
      end
    end
  end
end
