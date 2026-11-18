# frozen_string_literal: true

require "open3"
require "socket"

RSpec.describe "A process that loads the application" do
  def run_ruby(script, environment = {})
    environment_without_a_key_at_warn_level = {
      "APP_ENV" => "test", "CONFIGDIRECTOR_SERVER_KEY" => nil, "CONFIGDIRECTOR_LOG_LEVEL" => "warn"
    }
    Open3.capture3(
      environment_without_a_key_at_warn_level.merge(environment), RbConfig.ruby, "-r", "./app", "-e", script,
      chdir: File.expand_path("..", __dir__)
    )
  end

  it "registers no provider and creates no ConfigDirector client without a server SDK key" do
    output, errors, status = run_ruby(
      "print [OpenFeature::SDK.provider, ObjectSpace.each_object(ConfigDirector::ConfigDirectorClient).count].inspect"
    )

    expect([errors, status.exitstatus]).to eq(["", 0])
    expect(output).to eq("[nil, 0]")
  end

  it "connects to ConfigDirector on its first request" do
    stand_in_for_configdirector = TCPServer.new("127.0.0.1", 0)
    base_url = "http://127.0.0.1:#{stand_in_for_configdirector.local_address.ip_port}"
    first_request_line = Thread.new do
      connection = stand_in_for_configdirector.accept
      stand_in_for_configdirector.close
      connection.gets.tap { connection.close }
    end

    run_ruby(
      'Rack::MockRequest.new(SinatraSample).get("/configs")',
      "CONFIGDIRECTOR_BASE_URL" => base_url, "CONFIGDIRECTOR_TIMEOUT" => "0.5"
    )

    expect(first_request_line.join(5)&.value).to start_with("POST /server/sse/v1 ")
  ensure
    stand_in_for_configdirector&.close
  end

  it "closes the provider's ConfigDirector client when it exits" do
    output, errors, = run_ruby(<<~RUBY, "CONFIGDIRECTOR_MODE" => "offline")
      client = nil
      at_exit { print client.closed? }
      Rack::MockRequest.new(SinatraSample).get("/configs")
      client = ObjectSpace.each_object(ConfigDirector::ConfigDirectorClient).first
    RUBY

    expect(errors).to eq("")
    expect(output).to eq("true")
  end
end
