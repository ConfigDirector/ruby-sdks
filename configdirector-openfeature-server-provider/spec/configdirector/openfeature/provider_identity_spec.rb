# frozen_string_literal: true

require_relative "../../support/provider_over_the_scripted_sdk_server"

RSpec.describe "The identity of a ConfigDirector OpenFeature provider" do
  include_context "with a provider over the scripted SDK server"

  it "names the OpenFeature provider and its gem's version to the SDK server" do
    stream_request = register_over_a_stream_carrying(provider_connecting_to_the_sdk_server)

    expect(stream_request.headers["user-agent"]).to eq(
      "ruby-openfeature-server-provider/#{ConfigDirector::OpenFeature::VERSION}"
    )
    expect(stream_request.json["metaContext"]).to eq(
      "sdkName" => "ruby-openfeature-server-provider", "sdkVersion" => ConfigDirector::OpenFeature::VERSION
    )
  end

  it "is named ConfigDirectorProvider to OpenFeature" do
    register_over_a_stream_carrying(provider_connecting_to_the_sdk_server)

    expect(open_feature.provider_metadata.name).to eq("ConfigDirectorProvider")
  end
end
