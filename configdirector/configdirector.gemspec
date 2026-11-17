# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "configdirector"
  spec.version = "0.1.0"
  spec.authors = ["ConfigDirector"]
  spec.summary = "Installs configdirector-server-sdk, the Ruby server SDK for ConfigDirector."
  spec.description = "Installs configdirector-server-sdk, the Ruby server SDK for ConfigDirector. " \
                     "ConfigDirector is a remote configuration and feature flag service."
  spec.homepage = "https://www.configdirector.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata = {
    "documentation_uri" => "https://docs.configdirector.com/sdks/server/ruby",
    "source_code_uri" => "https://github.com/ConfigDirector/ruby-sdks/tree/main/configdirector",
    "changelog_uri" => "https://github.com/ConfigDirector/ruby-sdks/blob/main/configdirector/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.glob(["CHANGELOG.md", "LICENSE", "README.md"], base: __dir__)

  spec.add_dependency "configdirector-server-sdk", ">= 0.1.0", "< 1"
end
