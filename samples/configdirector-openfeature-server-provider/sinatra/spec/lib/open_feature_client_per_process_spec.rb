# frozen_string_literal: true

RSpec.describe OpenFeatureClientPerProcess do
  def with_environment(variables)
    variables_before = variables.keys.to_h { |name| [name, ENV.fetch(name, nil)] }
    ENV.update(variables)
    yield
  ensure
    ENV.update(variables_before)
  end

  it "creates the provider with the server SDK key, connection mode, timeout, base URL and log level the environment " \
     "names" do
    with_environment(
      "CONFIGDIRECTOR_SERVER_KEY" => "server-key-from-the-environment",
      "CONFIGDIRECTOR_MODE" => "polling",
      "CONFIGDIRECTOR_TIMEOUT" => "1.5",
      "CONFIGDIRECTOR_BASE_URL" => "https://configdirector-proxy.example.com",
      "CONFIGDIRECTOR_LOG_LEVEL" => "debug"
    ) do
      described_class.client
    end

    expect(ConfigDirector::OpenFeature::ConfigDirectorProvider).to have_received(:new).with(
      "server-key-from-the-environment",
      metadata: ConfigDirector::Metadata.new(app_name: "openfeature-sinatra-sample", app_version: "1.0.0"),
      connection: ConfigDirector::ConnectionOptions.new(
        mode: "polling", timeout: 1.5, url: "https://configdirector-proxy.example.com"
      ),
      logger: an_object_having_attributes(level: Logger::DEBUG)
    )
  end

  it "creates the provider with the sample key, the SDK's connection defaults and info level when the environment " \
     "names none" do
    with_environment(
      "CONFIGDIRECTOR_SERVER_KEY" => nil,
      "CONFIGDIRECTOR_MODE" => nil,
      "CONFIGDIRECTOR_TIMEOUT" => nil,
      "CONFIGDIRECTOR_BASE_URL" => nil,
      "CONFIGDIRECTOR_LOG_LEVEL" => nil
    ) do
      described_class.client
    end

    expect(ConfigDirector::OpenFeature::ConfigDirectorProvider).to have_received(:new).with(
      "fake-sample-key",
      metadata: ConfigDirector::Metadata.new(app_name: "openfeature-sinatra-sample", app_version: "1.0.0"),
      connection: ConfigDirector::ConnectionOptions.new,
      logger: an_object_having_attributes(level: Logger::INFO)
    )
  end

  it "reads a variable set to an empty value as not set" do
    with_environment(
      "CONFIGDIRECTOR_SERVER_KEY" => "",
      "CONFIGDIRECTOR_MODE" => "",
      "CONFIGDIRECTOR_TIMEOUT" => "",
      "CONFIGDIRECTOR_BASE_URL" => "",
      "CONFIGDIRECTOR_LOG_LEVEL" => ""
    ) do
      described_class.client
    end

    expect(ConfigDirector::OpenFeature::ConfigDirectorProvider).to have_received(:new).with(
      "fake-sample-key",
      metadata: ConfigDirector::Metadata.new(app_name: "openfeature-sinatra-sample", app_version: "1.0.0"),
      connection: ConfigDirector::ConnectionOptions.new,
      logger: an_object_having_attributes(level: Logger::INFO)
    )
  end

  it "refuses a timeout that is not a number" do
    with_environment("CONFIGDIRECTOR_TIMEOUT" => "3 seconds") do
      expect { described_class.client }.to raise_error(ArgumentError)
    end
  end
end
