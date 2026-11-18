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

require "configdirector/openfeature"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.raise_errors_for_deprecations!
  config.raise_on_warning = true
  config.order = :random
  Kernel.srand(config.seed)

  config.after(:suite) do
    focused_or_pending_examples = RSpec.world.all_examples.select do |example|
      example.metadata[:focus] || example.execution_result.status == :pending
    end
    next if focused_or_pending_examples.empty?

    raise "Remove the focus, skip or pending from #{focused_or_pending_examples.map(&:location).join(", ")}"
  end
end
