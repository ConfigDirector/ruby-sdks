# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "configdirector-openfeature-server-provider"
  spec.version = File.read(File.join(__dir__, "lib/configdirector/openfeature/version.rb"))[/VERSION = "([^"]+)"/, 1]
  spec.authors = ["ConfigDirector"]
  spec.summary = "OpenFeature server provider for ConfigDirector."
  spec.description = "OpenFeature server provider for ConfigDirector. " \
                     "ConfigDirector is a remote configuration and feature flag service."
  spec.homepage = "https://www.configdirector.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata = {
    "source_code_uri" =>
      "https://github.com/ConfigDirector/ruby-sdks/tree/main/configdirector-openfeature-server-provider",
    "changelog_uri" =>
      "https://github.com/ConfigDirector/ruby-sdks/blob/main/configdirector-openfeature-server-provider/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.glob(["lib/**/*.rb", "sig/**/*.rbs", "CHANGELOG.md", "LICENSE", "README.md"], base: __dir__)

  spec.add_dependency "configdirector-server-sdk", "0.1.0-dev"
  spec.add_dependency "openfeature-sdk", ">= 0.8.1", "< 0.9"
end
