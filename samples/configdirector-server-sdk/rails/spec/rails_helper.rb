# frozen_string_literal: true

module RaiseOnRubyWarning
  def warn(message, category: nil, **)
    raise "Ruby warned#{" (#{category})" if category}: #{message}"
  end
end

$VERBOSE = true
Warning[:deprecated] = true
Warning[:performance] = true
Warning.extend(RaiseOnRubyWarning)

ENV["RAILS_ENV"] = "test"

require_relative "../config/environment"
require "rspec/rails"
require_relative "support/five_standard_configs"
require_relative "support/local_sdk_server"

local_sdk_server = LocalSdkServer.new(FiveStandardConfigs::PAYLOAD_TEXT)
ENV["CONFIGDIRECTOR_BASE_URL"] = local_sdk_server.url

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.raise_errors_for_deprecations!
  config.raise_on_warning = true
  config.order = :random
  Kernel.srand(config.seed)

  config.after do
    ConfigDirectorClientPerProcess.instance_variable_get(:@client)&.close
    ConfigDirectorClientPerProcess.instance_variable_set(:@client, nil)
  end

  config.after(:suite) { local_sdk_server.stop }

  config.after(:suite) do
    focused_or_pending_examples = RSpec.world.all_examples.select do |example|
      example.metadata[:focus] || example.execution_result.status == :pending
    end
    next if focused_or_pending_examples.empty?

    raise "Remove the focus, skip or pending from #{focused_or_pending_examples.map(&:location).join(", ")}"
  end
end
