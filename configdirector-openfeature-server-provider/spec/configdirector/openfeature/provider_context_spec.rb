# frozen_string_literal: true

require "date"
require_relative "../../support/provider_over_the_scripted_sdk_server"

RSpec.describe "The context a ConfigDirector OpenFeature provider evaluates for" do
  include_context "with a provider over the scripted SDK server"

  let(:client) do
    open_feature_client_serving(
      wire_config(
        "plan-banner", "standard", rules: [wire_rule_serving("pro", conditions: [wire_trait_condition("/plan", "pro")])]
      ),
      wire_config("checkout", "old-checkout", rules: [wire_rollout_to_everyone("new-checkout")])
    )
  end

  def read_plan_banner_for(**fields)
    client.fetch_string_details(
      flag_key: "plan-banner", default_value: "in-code",
      evaluation_context: OpenFeature::SDK::EvaluationContext.new(**fields)
    )
  end

  it "evaluates for the targeting key, kind, name and traits of the evaluation context" do
    details = read_plan_banner_for(
      targeting_key: "org-1", kind: "organization", name: "Acme", traits: { "plan" => "pro" }
    )

    expect(details.value).to eq("pro")
    expect(captured_contexts_reported_at_shutdown).to eq(
      [{ "id" => "org-1", "kind" => "organization", "name" => "Acme", "traits" => { "plan" => "pro" } }]
    )
  end

  it "evaluates for an id attribute when the evaluation context has no targeting key" do
    read_plan_banner_for(id: "user-2")

    expect(captured_contexts_reported_at_shutdown).to eq([{ "id" => "user-2", "kind" => "user" }])
  end

  it "evaluates for the targeting key rather than an id attribute" do
    read_plan_banner_for(targeting_key: "user-1", id: "user-2")

    expect(captured_contexts_reported_at_shutdown).to eq([{ "id" => "user-1", "kind" => "user" }])
  end

  describe "identifier and name given as other Ruby values" do
    it "reads an Integer as its digits" do
      read_plan_banner_for(targeting_key: 42)

      expect(captured_contexts_reported_at_shutdown).to eq([{ "id" => "42", "kind" => "user" }])
    end

    it "reads a Float as its text" do
      read_plan_banner_for(targeting_key: 4.5)

      expect(captured_contexts_reported_at_shutdown).to eq([{ "id" => "4.5", "kind" => "user" }])
    end

    it "reads true as the text true" do
      read_plan_banner_for(targeting_key: true)

      expect(captured_contexts_reported_at_shutdown).to eq([{ "id" => "true", "kind" => "user" }])
    end

    it "reads a Symbol as its name" do
      read_plan_banner_for(targeting_key: :"user-1", name: :Ada)

      expect(captured_contexts_reported_at_shutdown).to eq([{ "id" => "user-1", "kind" => "user", "name" => "Ada" }])
    end

    it "reads a Time as UTC text with milliseconds" do
      read_plan_banner_for(targeting_key: Time.new(2026, 11, 17, 11, 30, 5.25r, "+01:00"))

      expect(captured_contexts_reported_at_shutdown).to eq([{ "id" => "2026-11-17T10:30:05.250Z", "kind" => "user" }])
    end

    it "reads a DateTime as UTC text with milliseconds" do
      read_plan_banner_for(targeting_key: DateTime.new(2026, 11, 17, 11, 30, 5, "+01:00"))

      expect(captured_contexts_reported_at_shutdown).to eq([{ "id" => "2026-11-17T10:30:05.000Z", "kind" => "user" }])
    end

    it "reads a Date as its calendar date" do
      read_plan_banner_for(targeting_key: Date.new(2026, 11, 17))

      expect(captured_contexts_reported_at_shutdown).to eq([{ "id" => "2026-11-17", "kind" => "user" }])
    end

    it "leaves out an identifier that is a Hash, so the context skips a percentage rollout" do
      details = client.fetch_string_details(
        flag_key: "checkout", default_value: "in-code",
        evaluation_context: OpenFeature::SDK::EvaluationContext.new(targeting_key: { "id" => "user-1" })
      )

      expect(details.value).to eq("old-checkout")
      expect(details.reason).to eq("DEFAULT")
      expect(details.variant).to eq("value-id-of-checkout")
      expect(details.error_code).to be_nil
    end
  end

  it "resolves a percentage rollout for a context without a targeting key or an id attribute with the reason DEFAULT" do
    details = client.fetch_string_details(
      flag_key: "checkout", default_value: "in-code",
      evaluation_context: OpenFeature::SDK::EvaluationContext.new(name: "Ada")
    )

    expect(details.value).to eq("old-checkout")
    expect(details.reason).to eq("DEFAULT")
    expect(details.variant).to eq("value-id-of-checkout")
    expect(details.error_code).to be_nil
  end

  describe "kind" do
    it "keeps a kind inside the traits as an ordinary trait" do
      read_plan_banner_for(targeting_key: "user-1", traits: { "kind" => "organization" })

      expect(captured_contexts_reported_at_shutdown).to eq(
        [{ "id" => "user-1", "kind" => "user", "traits" => { "kind" => "organization" } }]
      )
    end

    it "resolves a read for a context whose kind is not text to the value for no context, without an error" do
      details = read_plan_banner_for(targeting_key: "user-1", kind: 42, traits: { "plan" => "pro" })

      expect(details.value).to eq("standard")
      expect(details.reason).to eq("TARGETING_MATCH")
      expect(details.error_code).to be_nil
    end
  end

  describe "traits" do
    it "writes a date in the traits as UTC text with milliseconds, so date conditions can compare it" do
      read_plan_banner_for(targeting_key: "user-1", traits: { "signed_up" => Time.utc(2026, 11, 17, 10) })

      expect(captured_contexts_reported_at_shutdown.first.fetch("traits")).to eq(
        "signed_up" => "2026-11-17T10:00:00.000Z"
      )
    end

    it "writes dates inside a Hash and an Array of the traits as text" do
      read_plan_banner_for(
        targeting_key: "user-1",
        traits: { "account" => { "created" => Date.new(2026, 1, 2), "logins" => [Time.utc(2026, 11, 17, 10)] } }
      )

      expect(captured_contexts_reported_at_shutdown.first.fetch("traits")).to eq(
        "account" => { "created" => "2026-01-02", "logins" => ["2026-11-17T10:00:00.000Z"] }
      )
    end

    it "leaves out traits that are not a Hash" do
      details = read_plan_banner_for(targeting_key: "user-1", traits: "pro")

      expect(details.error_code).to be_nil
      expect(captured_contexts_reported_at_shutdown).to eq([{ "id" => "user-1", "kind" => "user" }])
    end

    it "leaves out traits that are an empty Hash" do
      read_plan_banner_for(targeting_key: "user-1", traits: {})

      expect(captured_contexts_reported_at_shutdown).to eq([{ "id" => "user-1", "kind" => "user" }])
    end

    it "resolves a read for traits that hold themselves to the in-code default value with GENERAL" do
      traits = { "plan" => "pro" }
      traits["itself"] = traits

      details = read_plan_banner_for(targeting_key: "user-1", traits: traits)

      expect(details.value).to eq("in-code")
      expect(details.reason).to eq("ERROR")
      expect(details.error_code).to eq("GENERAL")
    end
  end

  describe "anonymous" do
    it "does not keep a context whose anonymous attribute is true" do
      read_plan_banner_for(targeting_key: "user-1", anonymous: true)

      expect(captured_contexts_reported_at_shutdown).to eq([])
    end

    it "keeps a context whose anonymous attribute is not true" do
      read_plan_banner_for(targeting_key: "user-1", anonymous: "yes")

      expect(captured_contexts_reported_at_shutdown).to eq([{ "id" => "user-1", "kind" => "user" }])
    end
  end
end
