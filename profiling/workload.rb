# frozen_string_literal: true

require "etc"
require "json"
require "logger"
require "rbconfig"

SDK_DIRECTORY = File.expand_path("../configdirector-server-sdk", __dir__)
$LOAD_PATH.unshift(File.join(SDK_DIRECTORY, "lib"))

require "configdirector"
require File.join(SDK_DIRECTORY, "spec/support/elapsed_seconds")
require File.join(SDK_DIRECTORY, "spec/support/scripted_sdk_server")
require File.join(SDK_DIRECTORY, "spec/support/wire_payloads")

module Workload
  extend WirePayloads
  extend ElapsedSeconds

  CONFIG_COUNT = 200
  CONFIG_KEYS = Array.new(CONFIG_COUNT) { |index| "config-#{index}" }.freeze
  SEGMENTS = {
    "beta" => wire_segment_of_contexts_with_trait("/plan", "pro"),
    "staff" => wire_segment_of_contexts_with_trait("/company/name", "ConfigDirector")
  }.freeze

  def self.payload_text
    configs = CONFIG_KEYS.map do |config_key|
      wire_config(config_key, "value-of-#{config_key}", rules: rules_of(config_key))
    end

    full_payload_text(configs: configs, segments: SEGMENTS)
  end

  def self.rules_of(config_key)
    staff_conditions = [wire_trait_condition("/country", "UY"), wire_segment_condition("staff")]
    beta_conditions = [wire_segment_condition("beta")]

    [
      wire_rule_serving("staff-value-of-#{config_key}", conditions: staff_conditions),
      wire_rule_serving("beta-value-of-#{config_key}", conditions: beta_conditions).merge("order" => 1),
      wire_rollout_to_everyone("rollout-value-of-#{config_key}").merge("order" => 2)
    ]
  end

  def self.context_of_user(number)
    ConfigDirector::Context.new(
      id: "user-#{number}", name: "User #{number}",
      traits: { plan: "team", country: "UY", company: { name: "Acme", seats: 25 } }
    )
  end

  def self.sdk_server_opening_every_stream_with(payload_text)
    sdk_server = ScriptedSdkServer.new
    stream_requests = Queue.new
    Thread.new { loop { stream_requests << stream_opened_on(sdk_server, payload_text) } }

    [sdk_server, stream_requests]
  end

  def self.stream_opened_on(sdk_server, payload_text)
    stream_request = sdk_server.request_to(ScriptedSdkServer::STREAM_PATH, within: nil)
    stream_request.open_event_stream
    stream_request.send_event(payload_text)
    stream_request
  end

  def self.client_of(sdk_server_url)
    ConfigDirector.create_client(
      "server-sdk-key",
      connection: ConfigDirector::ConnectionOptions.new(url: sdk_server_url, timeout: 10),
      metadata: ConfigDirector::Metadata.new(app_name: "profiling", app_version: "1.0.0"),
      logger: Logger.new(File::NULL)
    )
  end

  def self.median_of(numbers)
    numbers.sort[numbers.length / 2]
  end

  def self.description_of_the_machine
    host_os = RbConfig::CONFIG.fetch("host_os")

    "#{RUBY_DESCRIPTION}, #{name_of_the_processor(host_os)}, #{Etc.nprocessors} cores, #{host_os}"
  end

  def self.name_of_the_processor(host_os)
    if host_os.include?("darwin")
      `sysctl -n machdep.cpu.brand_string`.strip
    elsif host_os.include?("linux")
      File.readlines("/proc/cpuinfo").find { |line| line.start_with?("model name") }.to_s.split(":", 2).last.to_s.strip
    else
      "an unnamed processor"
    end
  end

  private_constant :SEGMENTS
  private_class_method :rules_of, :stream_opened_on, :name_of_the_processor
end
