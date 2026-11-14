# frozen_string_literal: true

RSpec.describe "A route other than GET /configs", type: :request do
  it "answers 404 with a hint to GET /configs" do
    get "/other"

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["error"]).to include("GET /configs")
  end

  it "answers 404 with a hint to GET /configs for another method on /configs" do
    post "/configs"

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["error"]).to include("GET /configs")
  end

  it "answers 404 with a hint to GET /configs for /configs with a format extension" do
    get "/configs.json"

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["error"]).to include("GET /configs")
  end
end
