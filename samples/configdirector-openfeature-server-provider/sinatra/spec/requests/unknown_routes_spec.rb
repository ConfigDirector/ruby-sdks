# frozen_string_literal: true

RSpec.describe "A route other than GET /configs and GET /configs/<key>", type: :request do
  it "answers 404 with a hint to GET /configs" do
    get "/other"

    expect(last_response.status).to eq(404)
    expect(last_response.media_type).to eq("application/json")
    expect(JSON.parse(last_response.body)["error"]).to include("GET /configs")
  end

  it "answers 404 with a hint to GET /configs for another method on /configs" do
    post "/configs"

    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body)["error"]).to include("GET /configs")
  end
end
