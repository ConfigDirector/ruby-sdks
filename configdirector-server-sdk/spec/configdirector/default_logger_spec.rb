# frozen_string_literal: true

require_relative "../support/sdk_server_serving_the_sample_configs"

RSpec.describe "The default logger" do
  include_context "with an SDK server that serves the sample configs"

  def polling_every_30_seconds
    ConfigDirector::ConnectionOptions.new(mode: "polling", polling_interval: 30)
  end

  def invalid_context
    ConfigDirector::Context.new(kind: "Device")
  end

  it "writes a warning to standard error" do
    expect { ConfigDirector.create_client("server-sdk-key", connection: polling_every_30_seconds) }
      .to output(/\A\[ConfigDirector:ruby-server-sdk\] WARN: \[ConfigDirectorClient\] [^\n]*\b30\b[^\n]*\n\z/).to_stderr
  end

  it "writes an error to standard error" do
    expect { ConfigDirector.create_client("server-sdk-key").get_value("integer-config", 10, invalid_context) }
      .to output(/\A\[ConfigDirector:ruby-server-sdk\] ERROR: \[ConfigDirectorClient\] [^\n]*Device[^\n]*\n\z/)
      .to_stderr
  end

  it "writes nothing below a warning" do
    expect { client_of_the_sample_configs.tap(&:init).get_value("integer-config", 10) }
      .not_to output.to_stderr
  end

  it "writes nothing to standard output" do
    expect { ConfigDirector.create_client("server-sdk-key", connection: polling_every_30_seconds) }
      .not_to output.to_stdout
  end

  it "writes debug lines when the log level is :debug" do
    expect { client_of_the_sample_configs(log_level: :debug).tap(&:init) }
      .to output(/^\[ConfigDirector:ruby-server-sdk\] DEBUG: \[ConfigDirectorClient\] /).to_stderr
  end

  it "takes the log level as a String" do
    expect { client_of_the_sample_configs(log_level: "debug").tap(&:init) }
      .to output(/DEBUG/).to_stderr
  end

  it "takes the log level as a Logger constant" do
    expect { client_of_the_sample_configs(log_level: Logger::DEBUG).tap(&:init) }
      .to output(/DEBUG/).to_stderr
  end

  it "writes no warning when the log level is :error" do
    expect do
      ConfigDirector.create_client("server-sdk-key", connection: polling_every_30_seconds, log_level: :error)
    end.not_to output.to_stderr
  end

  it "rejects a log level that Ruby's Logger does not take" do
    expect { ConfigDirector.create_client("server-sdk-key", log_level: :verbose) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a log level that is a number Ruby's Logger has no level for" do
    expect { ConfigDirector.create_client("server-sdk-key", log_level: 99) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "rejects a log level of false" do
    expect { ConfigDirector.create_client("server-sdk-key", log_level: false) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "leaves the log level to the logger that is given" do
    logger = Logger.new(IO::NULL)

    expect { ConfigDirector.create_client("server-sdk-key", logger: logger, log_level: :verbose) }
      .not_to raise_error
  end
end
