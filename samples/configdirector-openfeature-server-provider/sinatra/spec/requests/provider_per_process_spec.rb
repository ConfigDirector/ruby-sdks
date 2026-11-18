# frozen_string_literal: true

RSpec.describe "The ConfigDirector provider of a process", type: :request do
  it "is registered on the first request and serves every later request" do
    read_config_keys = []
    in_memory_provider.update_flags(
      FiveStandardConfigs::VALUES.to_h do |config_key, value|
        value_recording_the_read = lambda do |_evaluation_context|
          read_config_keys << config_key
          value
        end
        [config_key, value_recording_the_read]
      end
    )

    get "/configs"
    get "/configs"

    expect(read_config_keys).to eq(
      %w[
        temporary-feature-flag permanent-kill-switch integer-config day-of-the-week-config json-value-config
        temporary-feature-flag permanent-kill-switch integer-config day-of-the-week-config json-value-config
      ]
    )
    expect(ConfigDirector::OpenFeature::ConfigDirectorProvider).to have_received(:new).once
  end

  it "is registered once when the first two requests of a process arrive together" do
    provider = in_memory_provider
    threads_creating_a_provider = Queue.new
    second_creation = Queue.new
    allow(ConfigDirector::OpenFeature::ConfigDirectorProvider).to receive(:new) do
      first_creation = threads_creating_a_provider.empty?
      threads_creating_a_provider << Thread.current
      if first_creation
        second_creation.pop(timeout: 0.5)
      else
        second_creation << :arrived
      end
      provider
    end

    statuses = Array.new(2) do
      Thread.new { Rack::MockRequest.new(SinatraSample).get("/configs").status }
    end.map(&:value)

    expect(statuses).to eq([200, 200])
    expect(threads_creating_a_provider.size).to eq(1)
  end

  it "keeps serving through the provider it registered, and logs a warning, when no config arrives in time" do
    provider_that_gets_no_config_in_time = Class.new(OpenFeature::SDK::Provider::InMemoryProvider) do
      def init
        raise OpenFeature::SDK::EvaluationError.new(
          "No config arrived in time", error_code: OpenFeature::SDK::Provider::ErrorCode::PROVIDER_NOT_READY
        )
      end
    end.new
    allow(ConfigDirector::OpenFeature::ConfigDirectorProvider).to receive(:new)
      .and_return(provider_that_gets_no_config_in_time)

    get "/configs"
    status_of_the_first_request = last_response.status
    get "/configs"

    expect([status_of_the_first_request, last_response.status]).to eq([200, 200])
    expect(ConfigDirector::OpenFeature::ConfigDirectorProvider).to have_received(:new).once
    expect(log.string).to match(/WARN -- : .*No config arrived in time/)
  end
end
