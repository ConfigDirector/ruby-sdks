# frozen_string_literal: true

require_relative "../../support/provider_over_the_scripted_sdk_server"

RSpec.describe "The configuration-changed events of a ConfigDirector OpenFeature provider" do
  include_context "with a provider over the scripted SDK server"

  def configuration_changes_sent
    changes = Queue.new
    open_feature.add_handler(
      OpenFeature::SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, ->(event_details) { changes << event_details }
    )
    changes
  end

  it "names the config a changed value belongs to" do
    stream_request = register_over_a_stream_carrying(
      provider_connecting_to_the_sdk_server, wire_config("greeting", "hello"), wire_config("farewell", "bye")
    )
    changes = configuration_changes_sent

    stream_request.send_event(delta_payload_text(configs: [wire_config("greeting", "hi")]))

    expect(changes.pop(timeout: 5)).to eq(provider_name: "ConfigDirectorProvider", flags_changed: ["greeting"])
  end

  it "names the configs an update removed after the configs it carried" do
    stream_request = register_over_a_stream_carrying(
      provider_connecting_to_the_sdk_server, wire_config("greeting", "hello"), wire_config("farewell", "bye")
    )
    changes = configuration_changes_sent

    stream_request.send_event(full_payload_text(configs: [wire_config("greeting", "hi")]))

    expect(changes.pop(timeout: 5)).to eq(
      provider_name: "ConfigDirectorProvider", flags_changed: %w[greeting farewell]
    )
  end
end
