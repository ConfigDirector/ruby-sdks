# frozen_string_literal: true

require_relative "../support/client_of_the_scripted_sdk_server"

RSpec.describe "Creating a client" do
  include_context "with a client of the scripted SDK server"

  def polling(polling_interval)
    ConfigDirector::ConnectionOptions.new(mode: "polling", polling_interval: polling_interval)
  end

  it "returns a ConfigDirectorClient that is not ready" do
    client = ConfigDirector.create_client("server-sdk-key", logger: logger)

    expect(client).to be_a(ConfigDirector::ConfigDirectorClient)
    expect(client.ready?).to be(false)
  end

  it "accepts every option" do
    client = ConfigDirector.create_client(
      "server-sdk-key",
      metadata: ConfigDirector::Metadata.new(app_name: "storefront", app_version: "1.4.0"),
      connection: ConfigDirector::ConnectionOptions.new(
        mode: "polling", polling_interval: 120, timeout: 5, url: sdk_server.url
      ),
      logger: logger,
      log_level: :debug,
      telemetry: ConfigDirector::TelemetryOptions.new(event_queue_limit: 100_000, flush_interval: 0.5),
      hooks: ConfigDirector::ClientHooks.new
    )
    clients_created << client

    initialize_with_a_first_poll_answered(client, status: 200, body: full_payload_text)

    expect(client.ready?).to be(true)
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "builds connection options for streaming from ConfigDirector with a 3 second timeout unless told otherwise" do
    connection = ConfigDirector::ConnectionOptions.new

    expect(connection.mode).to eq("streaming")
    expect(connection.url).to eq("https://server-sdk-api.configdirector.com")
    expect(connection.timeout).to eq(3)
    expect(connection.polling_interval).to eq(300)
    expect(connection.file).to be_nil
    expect(connection.values).to be_nil
  end

  it "builds telemetry options for 5,000 events sent every 30 seconds unless told otherwise" do
    telemetry = ConfigDirector::TelemetryOptions.new

    expect(telemetry.event_queue_limit).to eq(5_000)
    expect(telemetry.flush_interval).to eq(30)
  end

  it "builds option objects that cannot be changed" do
    expect(ConfigDirector::Metadata.new(app_name: "storefront")).to be_frozen
    expect(ConfigDirector::ConnectionOptions.new).to be_frozen
    expect(ConfigDirector::TelemetryOptions.new).to be_frozen
    expect(ConfigDirector::ClientHooks.new).to be_frozen
  end

  it "keeps the metadata it was built with when the Strings it was built from change" do
    app_name = +"storefront"
    metadata = ConfigDirector::Metadata.new(app_name: app_name)

    app_name << "-beta"

    expect(metadata.app_name).to eq("storefront")
  end

  it "keeps the connection options it was built with when what they were built from changes" do
    url = +"http://localhost:8080"
    values = { "new-checkout" => true, "sizes" => ["small"] }
    connection = ConfigDirector::ConnectionOptions.new(url: url, values: values)

    url << "/proxy"
    values["new-checkout"] = false
    values.fetch("sizes") << "large"

    expect(connection.url).to eq("http://localhost:8080")
    expect(connection.values).to eq({ "new-checkout" => true, "sizes" => ["small"] })
  end

  it "returns each hook as it was given" do
    ready_hook = -> {}
    evaluated_hooks = [->(_event) {}, ->(_event) {}]

    hooks = ConfigDirector::ClientHooks.new(client_ready: ready_hook, config_evaluated: evaluated_hooks)

    expect(hooks.client_ready).to be(ready_hook)
    expect(hooks.config_evaluated).to eq(evaluated_hooks)
    expect(hooks.configs_updated).to be_nil
    expect(hooks.connection_error).to be_nil
  end

  it "keeps the hooks it was built with when the Array they were built from changes" do
    first_hook = -> {}
    ready_hooks = [first_hook]
    hooks = ConfigDirector::ClientHooks.new(client_ready: ready_hooks)

    ready_hooks << -> {}

    expect(hooks.client_ready).to eq([first_hook])
  end

  it "compares connection options by their values" do
    expect(ConfigDirector::ConnectionOptions.new(mode: "polling"))
      .to eq(ConfigDirector::ConnectionOptions.new(mode: "polling"))
    expect(ConfigDirector::ConnectionOptions.new(mode: "polling")).not_to eq(ConfigDirector::ConnectionOptions.new)
  end

  it "compares option objects by their values" do
    expect(ConfigDirector::Metadata.new(app_name: "storefront"))
      .to eq(ConfigDirector::Metadata.new(app_name: "storefront"))
    expect(ConfigDirector::Metadata.new(app_name: "storefront"))
      .not_to eq(ConfigDirector::Metadata.new(app_name: "backoffice"))
  end

  it "rejects a missing server SDK key" do
    expect { ConfigDirector.create_client(logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a blank server SDK key" do
    expect { ConfigDirector.create_client("  ", logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a missing server SDK key in polling mode" do
    expect { ConfigDirector.create_client(connection: polling(300), logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "creates an offline client without a server SDK key" do
    client = ConfigDirector.create_client(
      connection: ConfigDirector::ConnectionOptions.new(mode: "offline"), logger: logger
    )

    expect(client).to be_a(ConfigDirector::ConfigDirectorClient)
  end

  it "rejects offline values given both as a file and as values" do
    connection = ConfigDirector::ConnectionOptions.new(mode: "offline", file: "flags.json", values: { "beta" => true })

    expect { ConfigDirector.create_client(connection: connection, logger: logger) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError, "An offline connection takes either 'file' or 'values', not both."
    )
  end

  it "rejects offline values in polling mode" do
    connection = ConfigDirector::ConnectionOptions.new(mode: "polling", values: { "beta" => true })

    expect { ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The connection options 'file' and 'values' apply only when the connection mode is 'offline', " \
      "but the mode is 'polling'."
    )
  end

  it "rejects an offline values file in streaming mode" do
    connection = ConfigDirector::ConnectionOptions.new(file: "flags.json")

    expect { ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The connection options 'file' and 'values' apply only when the connection mode is 'offline', " \
      "but the mode is 'streaming'."
    )
  end

  it "rejects offline values that are not a Hash" do
    connection = ConfigDirector::ConnectionOptions.new(mode: "offline", values: [["beta", true]])

    expect { ConfigDirector.create_client(connection: connection, logger: logger) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError, "Invalid 'values' option of class Array. It must be a Hash."
    )
  end

  it "rejects an offline values file that is neither a String nor a Pathname" do
    connection = ConfigDirector::ConnectionOptions.new(mode: "offline", file: File)

    expect { ConfigDirector.create_client(connection: connection, logger: logger) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "Invalid 'file' option of class Class. It must be a String or a Pathname."
    )
  end

  it "rejects an unknown connection mode" do
    connection = ConfigDirector::ConnectionOptions.new(mode: "push")

    expect { ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a connection mode given as a Symbol" do
    connection = ConfigDirector::ConnectionOptions.new(mode: :polling)

    expect { ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a url that is not http or https" do
    connection = ConfigDirector::ConnectionOptions.new(url: "ftp://example.com")

    expect { ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a url without a host" do
    connection = ConfigDirector::ConnectionOptions.new(url: "https://")

    expect { ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a url that cannot be parsed" do
    connection = ConfigDirector::ConnectionOptions.new(url: "https://example.com/a path")

    expect { ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "accepts any url in offline mode" do
    connection = ConfigDirector::ConnectionOptions.new(mode: "offline", url: "not a url")

    expect(ConfigDirector.create_client(connection: connection, logger: logger))
      .to be_a(ConfigDirector::ConfigDirectorClient)
  end

  it "rejects a timeout of 0" do
    connection = ConfigDirector::ConnectionOptions.new(timeout: 0)

    expect { ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a negative timeout" do
    connection = ConfigDirector::ConnectionOptions.new(timeout: -1)

    expect { ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a timeout that is not finite" do
    connection = ConfigDirector::ConnectionOptions.new(timeout: Float::INFINITY)

    expect { ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a timeout too large to be a finite number of seconds" do
    connection = ConfigDirector::ConnectionOptions.new(timeout: 10**400)

    expect { ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a timeout that is not a number" do
    connection = ConfigDirector::ConnectionOptions.new(timeout: "3")

    expect { ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "accepts a timeout of 0 in offline mode" do
    connection = ConfigDirector::ConnectionOptions.new(mode: "offline", timeout: 0)

    expect(ConfigDirector.create_client(connection: connection, logger: logger))
      .to be_a(ConfigDirector::ConfigDirectorClient)
  end

  it "accepts a negative timeout in offline mode" do
    connection = ConfigDirector::ConnectionOptions.new(mode: "offline", timeout: -1)

    expect(ConfigDirector.create_client(connection: connection, logger: logger))
      .to be_a(ConfigDirector::ConfigDirectorClient)
  end

  it "rejects a timeout that is not a number in offline mode" do
    connection = ConfigDirector::ConnectionOptions.new(mode: "offline", timeout: "3")

    expect { ConfigDirector.create_client(connection: connection, logger: logger) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError, "Invalid timeout '3'. The timeout must be a number of seconds."
    )
  end

  it "rejects an event queue limit of 50" do
    telemetry = ConfigDirector::TelemetryOptions.new(event_queue_limit: 50)

    expect { ConfigDirector.create_client("server-sdk-key", telemetry: telemetry, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "accepts an event queue limit of 100" do
    telemetry = ConfigDirector::TelemetryOptions.new(event_queue_limit: 100)

    expect(ConfigDirector.create_client("server-sdk-key", telemetry: telemetry, logger: logger))
      .to be_a(ConfigDirector::ConfigDirectorClient)
  end

  it "rejects an event queue limit of 100,001" do
    telemetry = ConfigDirector::TelemetryOptions.new(event_queue_limit: 100_001)

    expect { ConfigDirector.create_client("server-sdk-key", telemetry: telemetry, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects an event queue limit that is not a whole number" do
    telemetry = ConfigDirector::TelemetryOptions.new(event_queue_limit: 500.5)

    expect { ConfigDirector.create_client("server-sdk-key", telemetry: telemetry, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a flush interval of 0" do
    telemetry = ConfigDirector::TelemetryOptions.new(flush_interval: 0)

    expect { ConfigDirector.create_client("server-sdk-key", telemetry: telemetry, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a Hash given as the connection options" do
    expect { ConfigDirector.create_client("server-sdk-key", connection: { mode: "polling" }, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a Hash given as the metadata" do
    expect { ConfigDirector.create_client("server-sdk-key", metadata: { app_name: "storefront" }, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a Hash given as the telemetry options" do
    expect { ConfigDirector.create_client("server-sdk-key", telemetry: { flush_interval: 5 }, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a Hash given as the hooks" do
    expect { ConfigDirector.create_client("server-sdk-key", hooks: {}, logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a logger that cannot log a warning" do
    expect { ConfigDirector.create_client("server-sdk-key", logger: Object.new) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "logs one warning for a polling interval of 30 seconds" do
    ConfigDirector.create_client("server-sdk-key", connection: polling(30), logger: logger)

    expect(logger.messages_at(:warn).length).to eq(1)
  end

  it "logs no warning for a polling interval of 60 seconds" do
    ConfigDirector.create_client("server-sdk-key", connection: polling(60), logger: logger)

    expect(logger.messages_at(:warn)).to be_empty
  end

  it "logs no warning for a polling interval of 30 seconds in streaming mode" do
    connection = ConfigDirector::ConnectionOptions.new(mode: "streaming", polling_interval: 30)

    ConfigDirector.create_client("server-sdk-key", connection: connection, logger: logger)

    expect(logger.messages_at(:warn)).to be_empty
  end

  it "rejects a polling interval that is not a number" do
    expect { ConfigDirector.create_client("server-sdk-key", connection: polling("300"), logger: logger) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises an error that is a ConfigDirectorError and a StandardError" do
    expect(ConfigDirector::ConfigDirectorValidationError.ancestors)
      .to include(ConfigDirector::ConfigDirectorError, StandardError)
  end
end
