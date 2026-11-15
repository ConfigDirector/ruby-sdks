# frozen_string_literal: true

module FiveStandardConfigs
  VALUES = {
    "temporary-feature-flag" => true,
    "permanent-kill-switch" => true,
    "integer-config" => 42,
    "day-of-the-week-config" => "Tuesday",
    "json-value-config" => { "greeting" => "hello", "sizes" => [1, 2] }
  }.freeze
end
