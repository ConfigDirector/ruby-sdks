# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "configdirector-server-sdk"
  spec.version = File.read(File.join(__dir__, "lib/configdirector/version.rb"))[/VERSION = "([^"]+)"/, 1]
  spec.authors = ["ConfigDirector"]
  spec.summary = "Ruby server SDK for ConfigDirector."
  spec.description = "Ruby server SDK for ConfigDirector. " \
                     "ConfigDirector is a remote configuration and feature flag service."
  spec.homepage = "https://www.configdirector.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata = {
    "documentation_uri" => "https://docs.configdirector.com/sdks/server/ruby",
    "source_code_uri" => "https://github.com/ConfigDirector/ruby-sdks/tree/main/configdirector-server-sdk",
    "changelog_uri" => "https://github.com/ConfigDirector/ruby-sdks/blob/main/configdirector-server-sdk/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.glob(
    ["lib/**/*.rb", "sig/**/*.rbs", ".yardopts", "CHANGELOG.md", "LICENSE", "README.md"], base: __dir__
  )

  spec.add_dependency "logger", "~> 1.6"
  spec.add_dependency "net-http", ">= 0.10.0"
end
