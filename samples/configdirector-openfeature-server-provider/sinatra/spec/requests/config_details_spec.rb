# frozen_string_literal: true

RSpec.describe "GET /configs/<key>", type: :request do
  it "returns the value, variant and reason the boolean flag was evaluated to" do
    in_memory_provider.add_flag(
      flag_key: "permanent-kill-switch",
      value: OpenFeature::SDK::Provider::InMemoryProvider::Flag.new(
        variants: { "on" => true, "off" => false }, default_variant: "on"
      )
    )

    get "/configs/permanent-kill-switch?id=user-123"

    expect(last_response.status).to eq(200)
    expect(last_response.media_type).to eq("application/json")
    expect(JSON.parse(last_response.body)).to eq(
      "value" => true, "variant" => "on", "reason" => "STATIC", "error_code" => nil, "error_message" => nil
    )
  end

  it "explains why the in-code default value was served for a flag no config has" do
    get "/configs/no-such-flag?id=user-123"

    expect(JSON.parse(last_response.body)).to include(
      "value" => false, "reason" => "ERROR", "error_code" => "FLAG_NOT_FOUND"
    )
  end

  it "evaluates the flag for the context in the query string" do
    evaluated_contexts = []
    in_memory_provider.add_flag(
      flag_key: "temporary-feature-flag",
      value: lambda do |evaluation_context|
        evaluated_contexts << evaluation_context
        true
      end
    )

    get "/configs/temporary-feature-flag?id=user-123&name=Ada&anonymous=true&plan=pro"

    expect(evaluated_contexts).to eq(
      [
        OpenFeature::SDK::EvaluationContext.new(
          targeting_key: "user-123", name: "Ada", anonymous: true, traits: { "plan" => "pro" }
        )
      ]
    )
  end
end
