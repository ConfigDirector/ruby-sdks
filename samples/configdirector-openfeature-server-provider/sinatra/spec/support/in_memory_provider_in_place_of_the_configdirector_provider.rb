# frozen_string_literal: true

RSpec.shared_context "with an in-memory provider in place of the ConfigDirector provider" do
  let(:in_memory_provider) { OpenFeature::SDK::Provider::InMemoryProvider.new(FiveStandardConfigs::VALUES.dup) }

  before do
    allow(ConfigDirector::OpenFeature::ConfigDirectorProvider).to receive(:new).and_return(in_memory_provider)
  end
end
