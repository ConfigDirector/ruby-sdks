# frozen_string_literal: true

first_patched_release_by_line = {
  "3.3" => "3.3.13",
  "3.4" => "3.4.12",
  "4.0" => "4.0.9"
}

running_line = RUBY_VERSION.split(".").first(2).join(".")
first_patched_release = first_patched_release_by_line[running_line]
line_released_after_the_fixes = Gem::Version.new(running_line) > Gem::Version.new(first_patched_release_by_line.keys.last)

patched = if first_patched_release
            Gem::Version.new(RUBY_VERSION) >= Gem::Version.new(first_patched_release)
          else
            line_released_after_the_fixes
          end

puts "Ruby #{RUBY_VERSION}"

unless patched
  *older_patched_releases, newest_patched_release = first_patched_release_by_line.values
  warn "Ruby #{RUBY_VERSION} lacks the regular expression fixes of 2026-10-23, which arrived in Ruby " \
       "#{older_patched_releases.join(", ")} and #{newest_patched_release}. " \
       "Upgrade to one of those or a later release on the same line."
  exit 1
end
