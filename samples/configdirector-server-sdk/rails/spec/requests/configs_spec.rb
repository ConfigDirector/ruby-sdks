# frozen_string_literal: true

RSpec.describe "GET /configs", type: :request do
  it "returns the value each of the five configs serves to the context in the query string" do
    reasons_by_config_key = {}
    ConfigDirectorClientPerProcess.client.on(:config_evaluated) do |event|
      reasons_by_config_key[event.evaluation.key] = event.evaluation.reason
    end

    get "/configs?id=user-123&plan=pro"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "temporary-feature-flag" => true,
      "permanent-kill-switch" => true,
      "integer-config" => 42,
      "day-of-the-week-config" => "Tuesday",
      "json-value-config" => { "greeting" => "hello", "sizes" => [1, 2] }
    )
    expect(reasons_by_config_key).to eq(
      "temporary-feature-flag" => "found-match",
      "permanent-kill-switch" => "found-match",
      "integer-config" => "found-match",
      "day-of-the-week-config" => "found-match",
      "json-value-config" => "found-match"
    )
  end

  it "evaluates each config for the id, kind, name and anonymous flag in the query string, with the rest as traits" do
    evaluated_contexts = []
    ConfigDirectorClientPerProcess.client.on(:config_evaluated) do |event|
      evaluated_contexts << event.evaluation.context
    end

    get "/configs?id=user-123&kind=device&name=Ada&anonymous=true&plan=pro&region=eu"

    ada = ConfigDirector::Context.new(
      id: "user-123", kind: "device", name: "Ada", traits: { "plan" => "pro", "region" => "eu" }, anonymous: true
    )
    expect(evaluated_contexts).to eq([ada, ada, ada, ada, ada])
  end
end
