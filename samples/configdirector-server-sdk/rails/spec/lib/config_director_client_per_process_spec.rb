# frozen_string_literal: true

RSpec.describe ConfigDirectorClientPerProcess do
  def with_environment(variables)
    variables_before = variables.keys.to_h { |name| [name, ENV.fetch(name, nil)] }
    ENV.update(variables)
    yield
  ensure
    ENV.update(variables_before)
  end

  it "creates the client with the server SDK key, connection mode, timeout and base URL the environment names" do
    allow(ConfigDirector).to receive(:create_client).and_call_original

    with_environment(
      "CONFIGDIRECTOR_SERVER_KEY" => "server-key-from-the-environment",
      "CONFIGDIRECTOR_MODE" => "polling",
      "CONFIGDIRECTOR_TIMEOUT" => "1.5",
      "CONFIGDIRECTOR_BASE_URL" => "https://configdirector-proxy.example.com"
    ) do
      described_class.client
    end

    expect(ConfigDirector).to have_received(:create_client).with(
      "server-key-from-the-environment",
      metadata: ConfigDirector::Metadata.new(app_name: "rails-sample", app_version: "1.0.0"),
      connection: ConfigDirector::ConnectionOptions.new(
        mode: "polling", timeout: 1.5, url: "https://configdirector-proxy.example.com"
      ),
      logger: Rails.logger
    )
  end

  it "creates the client with the sample key and the SDK's connection defaults when the environment names none" do
    allow(ConfigDirector).to receive(:create_client).and_call_original

    with_environment(
      "CONFIGDIRECTOR_SERVER_KEY" => nil,
      "CONFIGDIRECTOR_MODE" => nil,
      "CONFIGDIRECTOR_TIMEOUT" => nil,
      "CONFIGDIRECTOR_BASE_URL" => nil
    ) do
      described_class.client
    end

    expect(ConfigDirector).to have_received(:create_client).with(
      "fake-sample-key",
      metadata: ConfigDirector::Metadata.new(app_name: "rails-sample", app_version: "1.0.0"),
      connection: ConfigDirector::ConnectionOptions.new,
      logger: Rails.logger
    )
  end

  it "reads a variable set to an empty value as not set" do
    allow(ConfigDirector).to receive(:create_client).and_call_original

    with_environment(
      "CONFIGDIRECTOR_SERVER_KEY" => "",
      "CONFIGDIRECTOR_MODE" => "",
      "CONFIGDIRECTOR_TIMEOUT" => "",
      "CONFIGDIRECTOR_BASE_URL" => ""
    ) do
      described_class.client
    end

    expect(ConfigDirector).to have_received(:create_client).with(
      "fake-sample-key",
      metadata: ConfigDirector::Metadata.new(app_name: "rails-sample", app_version: "1.0.0"),
      connection: ConfigDirector::ConnectionOptions.new,
      logger: Rails.logger
    )
  end

  it "refuses a timeout that is not a number" do
    with_environment("CONFIGDIRECTOR_TIMEOUT" => "3 seconds") do
      expect { described_class.client }.to raise_error(ArgumentError)
    end
  end
end
