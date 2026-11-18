# frozen_string_literal: true

require_relative "../../support/provider_over_the_scripted_sdk_server"

RSpec.describe "Events tracked through a ConfigDirector OpenFeature provider" do
  include_context "with a provider over the scripted SDK server"

  let(:client) { open_feature_client_serving }

  def tracked_events_reported_at_shutdown
    telemetry_reported_at_shutdown.fetch("trackedEvents").map { |tracked_event| tracked_event.except("happenedAt") }
  end

  it "reports a tracked event with its value, its other attributes as details, and the evaluation context" do
    client.track(
      "checkout-completed",
      evaluation_context: OpenFeature::SDK::EvaluationContext.new(targeting_key: "user-1"),
      tracking_event_details: OpenFeature::SDK::TrackingEventDetails.new(value: 49.9, plan: "pro")
    )

    expect(tracked_events_reported_at_shutdown).to eq(
      [
        {
          "name" => "checkout-completed", "contextKind" => "user", "contextIdentifier" => "user-1", "value" => 49.9,
          "details" => { "plan" => "pro" }
        }
      ]
    )
  end

  it "reports an event tracked without details or an evaluation context with its name alone" do
    client.track("checkout-completed")

    expect(tracked_events_reported_at_shutdown).to eq([{ "name" => "checkout-completed" }])
  end

  it "reports an event tracked with a value alone without details" do
    client.track(
      "checkout-completed", tracking_event_details: OpenFeature::SDK::TrackingEventDetails.new(value: 3)
    )

    expect(tracked_events_reported_at_shutdown).to eq([{ "name" => "checkout-completed", "value" => 3 }])
  end

  it "reports an event of a context marked anonymous without its kind or targeting key" do
    client.track(
      "checkout-completed",
      evaluation_context: OpenFeature::SDK::EvaluationContext.new(targeting_key: "user-1", anonymous: true)
    )

    expect(tracked_events_reported_at_shutdown).to eq([{ "name" => "checkout-completed" }])
  end

  it "logs a warning and leaves out an event whose evaluation context cannot be read" do
    traits = { "plan" => "pro" }
    traits["itself"] = traits

    client.track(
      "checkout-completed",
      evaluation_context: OpenFeature::SDK::EvaluationContext.new(targeting_key: "user-1", traits: traits)
    )
    client.track("page-viewed")

    expect(logger.messages_at(:warn)).to eq(
      [
        "A tracked event was not reported because it could not be read: Invalid context traits nested deeper " \
        "than 100 levels. A context's traits must be nested 100 levels deep or less, so a Hash or an Array among " \
        "them cannot hold itself."
      ]
    )
    expect(tracked_events_reported_at_shutdown).to eq([{ "name" => "page-viewed" }])
  end
end
