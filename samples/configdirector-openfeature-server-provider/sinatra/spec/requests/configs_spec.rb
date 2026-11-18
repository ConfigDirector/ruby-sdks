# frozen_string_literal: true

RSpec.describe "GET /configs", type: :request do
  it "returns the value each of the five configs serves" do
    get "/configs?id=user-123&plan=pro"

    expect(last_response.status).to eq(200)
    expect(last_response.media_type).to eq("application/json")
    expect(JSON.parse(last_response.body)).to eq(
      "temporary-feature-flag" => false,
      "permanent-kill-switch" => true,
      "integer-config" => 42,
      "day-of-the-week-config" => "Tuesday",
      "json-value-config" => { "greeting" => "hello", "sizes" => [1, 2] }
    )
  end

  it "returns the in-code default value of each config the provider does not serve" do
    in_memory_provider.update_flags({})

    get "/configs?id=user-123&plan=pro"

    expect(JSON.parse(last_response.body)).to eq(
      "temporary-feature-flag" => true,
      "permanent-kill-switch" => false,
      "integer-config" => 10,
      "day-of-the-week-config" => "Friday",
      "json-value-config" => {}
    )
  end

  it "returns the new value of a config that changes after the first request" do
    get "/configs"
    in_memory_provider.add_flag(flag_key: "integer-config", value: 7)

    get "/configs"

    expect(JSON.parse(last_response.body)["integer-config"]).to eq(7)
  end

  it "evaluates each config for the id, name and anonymous flag in the query string, with the rest as traits" do
    contexts_by_config_key = {}
    in_memory_provider.update_flags(
      FiveStandardConfigs::VALUES.to_h do |config_key, value|
        value_recording_the_context = lambda do |evaluation_context|
          contexts_by_config_key[config_key] = evaluation_context
          value
        end
        [config_key, value_recording_the_context]
      end
    )

    get "/configs?id=user-123&name=Ada&anonymous=true&plan=pro&region=eu"

    ada = OpenFeature::SDK::EvaluationContext.new(
      targeting_key: "user-123", name: "Ada", anonymous: true, traits: { "plan" => "pro", "region" => "eu" }
    )
    expect(contexts_by_config_key).to eq(
      "temporary-feature-flag" => ada,
      "permanent-kill-switch" => ada,
      "integer-config" => ada,
      "day-of-the-week-config" => ada,
      "json-value-config" => ada
    )
  end
end
