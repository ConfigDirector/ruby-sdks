# frozen_string_literal: true

require "open3"

RSpec.describe "A process that loads the application" do
  def run_rails_runner(script, environment = {})
    environment_without_settings = {
      "RAILS_ENV" => "test", "CONFIGDIRECTOR_SERVER_KEY" => nil, "CONFIGDIRECTOR_LOG_LEVEL" => nil
    }
    Open3.capture3(
      environment_without_settings.merge(environment), RbConfig.ruby, "bin/rails", "runner", script,
      chdir: Rails.root.to_s
    )
  end

  it "creates no client and raises nothing without a server SDK key when it reads no config" do
    output, errors, status = run_rails_runner(
      "Rails.application.eager_load!; print ObjectSpace.each_object(ConfigDirector::ConfigDirectorClient).count"
    )

    expect([errors, status.exitstatus]).to eq(["", 0])
    expect(output).to eq("0")
  end

  it "closes the client it created when it exits" do
    output, errors, = run_rails_runner(<<~RUBY)
      client = nil
      at_exit { print client.closed? }
      client = ConfigDirectorClientPerProcess.client
    RUBY

    expect(errors).to eq("")
    expect(output).to eq("true")
  end

  it "writes log lines at the level CONFIGDIRECTOR_LOG_LEVEL names" do
    output, errors, = run_rails_runner(
      "print [Rails.logger.info?, Rails.logger.warn?].inspect", "CONFIGDIRECTOR_LOG_LEVEL" => "warn"
    )

    expect(errors).to eq("")
    expect(output).to eq("[false, true]")
  end

  it "writes log lines at info level and above when CONFIGDIRECTOR_LOG_LEVEL is not set" do
    output, errors, = run_rails_runner("print [Rails.logger.debug?, Rails.logger.info?].inspect")

    expect(errors).to eq("")
    expect(output).to eq("[false, true]")
  end

  it "writes log lines at info level and above when CONFIGDIRECTOR_LOG_LEVEL is empty" do
    output, errors, = run_rails_runner(
      "print [Rails.logger.debug?, Rails.logger.info?].inspect", "CONFIGDIRECTOR_LOG_LEVEL" => ""
    )

    expect(errors).to eq("")
    expect(output).to eq("[false, true]")
  end
end
