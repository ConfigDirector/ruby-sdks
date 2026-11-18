# frozen_string_literal: true

require "open_feature/sdk"

module RaiseOnRubyWarning
  def warn(message, category: nil, **)
    raise "Ruby warned#{" (#{category})" if category}: #{message}"
  end
end

$VERBOSE = true
Warning[:deprecated] = true
Warning[:performance] = true
Warning.extend(RaiseOnRubyWarning)

ENV["APP_ENV"] = "test"

require "rack/test"
require_relative "../app"
require_relative "support/five_standard_configs"
require_relative "support/in_memory_provider_in_place_of_the_configdirector_provider"
require_relative "support/standard_output_captured_as_the_log"

module RequestsToTheSample
  include Rack::Test::Methods

  def app
    SinatraSample
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.raise_errors_for_deprecations!
  config.raise_on_warning = true
  config.order = :random
  Kernel.srand(config.seed)

  config.include RequestsToTheSample, type: :request
  config.include_context "with an in-memory provider in place of the ConfigDirector provider"
  config.include_context "with the standard output captured as the log"

  config.after do
    OpenFeature::SDK.shutdown
    OpenFeatureClientPerProcess.instance_variable_set(:@client, nil)
  end

  config.after(:suite) do
    focused_or_pending_examples = RSpec.world.all_examples.select do |example|
      example.metadata[:focus] || example.execution_result.status == :pending
    end
    next if focused_or_pending_examples.empty?

    raise "Remove the focus, skip or pending from #{focused_or_pending_examples.map(&:location).join(", ")}"
  end
end
