# frozen_string_literal: true

require_relative "../../support/provider_over_the_scripted_sdk_server"

RSpec.describe "Creating a ConfigDirector OpenFeature provider" do
  include_context "with a provider over the scripted SDK server"

  it "names the application's name and version to the SDK server" do
    provider = provider_connecting_to_the_sdk_server(
      metadata: ConfigDirector::Metadata.new(app_name: "checkout", app_version: "2.1.0")
    )

    stream_request = register_over_a_stream_carrying(provider)

    expect(stream_request.json.fetch("metaContext")).to include("appName" => "checkout", "appVersion" => "2.1.0")
  end

  it "raises ConfigDirectorValidationError for a blank server SDK key" do
    expect { ConfigDirector::OpenFeature::ConfigDirectorProvider.new(" ") }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError
    )
  end

  it "raises ConfigDirectorValidationError for a log level that is not one" do
    expect do
      ConfigDirector::OpenFeature::ConfigDirectorProvider.new("server-sdk-key", log_level: :loud)
    end.to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises ConfigDirectorValidationError for a telemetry flush interval that is not positive" do
    expect do
      ConfigDirector::OpenFeature::ConfigDirectorProvider.new(
        "server-sdk-key", telemetry: ConfigDirector::TelemetryOptions.new(flush_interval: 0)
      )
    end.to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end
end
