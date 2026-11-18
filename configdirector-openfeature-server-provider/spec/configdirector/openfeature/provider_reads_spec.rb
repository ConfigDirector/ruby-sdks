# frozen_string_literal: true

require_relative "../../support/provider_over_the_scripted_sdk_server"

RSpec.describe "Reads through a ConfigDirector OpenFeature provider" do
  include_context "with a provider over the scripted SDK server"

  it "resolves a boolean flag to its value with a targeting match and its value ID as the variant" do
    client = open_feature_client_serving(wire_config("new-checkout", "true", type: "boolean"))

    details = client.fetch_boolean_details(flag_key: "new-checkout", default_value: false)

    expect(details.value).to be(true)
    expect(details.reason).to eq("TARGETING_MATCH")
    expect(details.variant).to eq("value-id-of-new-checkout")
    expect(details.error_code).to be_nil
  end

  it "resolves a string flag to its value with a targeting match and its value ID as the variant" do
    client = open_feature_client_serving(wire_config("greeting", "hello"))

    details = client.fetch_string_details(flag_key: "greeting", default_value: "in-code")

    expect(details.value).to eq("hello")
    expect(details.reason).to eq("TARGETING_MATCH")
    expect(details.variant).to eq("value-id-of-greeting")
    expect(details.error_code).to be_nil
  end

  it "resolves an integer flag to its value with a targeting match and its value ID as the variant" do
    client = open_feature_client_serving(wire_config("page-size", "25", type: "integer"))

    details = client.fetch_integer_details(flag_key: "page-size", default_value: 10)

    expect(details.value).to eql(25)
    expect(details.reason).to eq("TARGETING_MATCH")
    expect(details.variant).to eq("value-id-of-page-size")
    expect(details.error_code).to be_nil
  end

  it "resolves a float flag to its value with a targeting match and its value ID as the variant" do
    client = open_feature_client_serving(wire_config("discount-rate", "0.15", type: "float"))

    details = client.fetch_float_details(flag_key: "discount-rate", default_value: 0.0)

    expect(details.value).to eql(0.15)
    expect(details.reason).to eq("TARGETING_MATCH")
    expect(details.variant).to eq("value-id-of-discount-rate")
    expect(details.error_code).to be_nil
  end

  it "resolves an object flag holding a JSON object to a Hash with a targeting match and its value ID as the variant" do
    client = open_feature_client_serving(wire_config("checkout-settings", '{"steps":3,"express":true}', type: "json"))

    details = client.fetch_object_details(flag_key: "checkout-settings", default_value: {})

    expect(details.value).to eq("steps" => 3, "express" => true)
    expect(details.reason).to eq("TARGETING_MATCH")
    expect(details.variant).to eq("value-id-of-checkout-settings")
    expect(details.error_code).to be_nil
  end

  it "resolves an object flag holding a JSON array to an Array with a targeting match and its value ID variant" do
    client = open_feature_client_serving(wire_config("supported-locales", '["en","fr"]', type: "json"))

    details = client.fetch_object_details(flag_key: "supported-locales", default_value: [])

    expect(details.value).to eq(%w[en fr])
    expect(details.reason).to eq("TARGETING_MATCH")
    expect(details.variant).to eq("value-id-of-supported-locales")
    expect(details.error_code).to be_nil
  end

  describe "of a number" do
    it "resolves a number flag holding a fraction to a Float when the in-code default value is an Integer" do
      client = open_feature_client_serving(wire_config("discount-rate", "2.5", type: "float"))

      details = client.fetch_number_details(flag_key: "discount-rate", default_value: 0)

      expect(details.value).to eql(2.5)
      expect(details.reason).to eq("TARGETING_MATCH")
      expect(details.variant).to eq("value-id-of-discount-rate")
      expect(details.error_code).to be_nil
    end

    it "resolves a number flag holding a whole number to an Integer when the in-code default value is a Float" do
      client = open_feature_client_serving(wire_config("page-size", "25", type: "integer"))

      details = client.fetch_number_details(flag_key: "page-size", default_value: 0.5)

      expect(details.value).to eql(25)
      expect(details.reason).to eq("TARGETING_MATCH")
      expect(details.error_code).to be_nil
    end

    it "resolves a number flag no config has the key of to the Integer in-code default value as given" do
      client = open_feature_client_serving

      details = client.fetch_number_details(flag_key: "no-such-config", default_value: 7)

      expect(details.value).to eql(7)
      expect(details.error_code).to eq("FLAG_NOT_FOUND")
    end

    it "resolves a number flag no config has the key of to a Rational in-code default value as given" do
      client = open_feature_client_serving

      details = client.fetch_number_details(flag_key: "no-such-config", default_value: Rational(1, 3))

      expect(details.value).to eql(Rational(1, 3))
      expect(details.error_code).to eq("FLAG_NOT_FOUND")
    end

    it "resolves a number flag holding text to the in-code default value as given with TYPE_MISMATCH" do
      client = open_feature_client_serving(wire_config("day-of-the-week", "Monday"))

      details = client.fetch_number_details(flag_key: "day-of-the-week", default_value: 5)

      expect(details.value).to eql(5)
      expect(details.error_code).to eq("TYPE_MISMATCH")
      expect(details.error_message).to eq(
        "The value of 'day-of-the-week' cannot be read as the requested type (invalid-number)."
      )
    end
  end

  describe "variant" do
    def checkout_serving_the_variation(variation)
      wire_config(
        "checkout", "old-checkout",
        rules: [wire_rule_serving("new-checkout", conditions: []).merge("variationId" => "variation-new")],
        variations: [variation]
      )
    end

    it "is the name of the variation served" do
      client = open_feature_client_serving(
        checkout_serving_the_variation({ "id" => "variation-new", "name" => "New checkout", "value" => "new-checkout" })
      )

      details = client.fetch_string_details(flag_key: "checkout", default_value: "in-code")

      expect(details.value).to eq("new-checkout")
      expect(details.variant).to eq("New checkout")
    end

    it "is the value ID when the variation served has no name" do
      client = open_feature_client_serving(
        checkout_serving_the_variation({ "id" => "variation-new", "value" => "new-checkout" })
      )

      details = client.fetch_string_details(flag_key: "checkout", default_value: "in-code")

      expect(details.value).to eq("new-checkout")
      expect(details.variant).to eq("value-id-of-new-checkout")
    end
  end

  it "resolves a flag whose config has no value to the in-code default value with the reason DEFAULT and no error" do
    client = open_feature_client_serving(wire_config("greeting", ""))

    details = client.fetch_string_details(flag_key: "greeting", default_value: "in-code")

    expect(details.value).to eq("in-code")
    expect(details.reason).to eq("DEFAULT")
    expect(details.variant).to be_nil
    expect(details.error_code).to be_nil
    expect(details.error_message).to be_nil
  end

  it "resolves a flag no config has the key of to the in-code default value with FLAG_NOT_FOUND" do
    client = open_feature_client_serving

    details = client.fetch_string_details(flag_key: "no-such-config", default_value: "in-code")

    expect(details.value).to eq("in-code")
    expect(details.reason).to eq("ERROR")
    expect(details.error_code).to eq("FLAG_NOT_FOUND")
    expect(details.error_message).to eq("No config with the key 'no-such-config' was found.")
  end

  describe "of a value that cannot be read as the requested type" do
    it "resolves a string read of an integer config to the in-code default value with TYPE_MISMATCH" do
      client = open_feature_client_serving(wire_config("page-size", "25", type: "integer"))

      details = client.fetch_string_details(flag_key: "page-size", default_value: "in-code")

      expect(details.value).to eq("in-code")
      expect(details.reason).to eq("ERROR")
      expect(details.error_code).to eq("TYPE_MISMATCH")
      expect(details.error_message).to eq(
        "The value of 'page-size' cannot be read as the requested type (type-mismatch)."
      )
    end

    it "resolves an integer read of text that is not a number to the in-code default value with TYPE_MISMATCH" do
      client = open_feature_client_serving(wire_config("day-of-the-week", "Monday"))

      details = client.fetch_integer_details(flag_key: "day-of-the-week", default_value: 5)

      expect(details.value).to eql(5)
      expect(details.reason).to eq("ERROR")
      expect(details.error_code).to eq("TYPE_MISMATCH")
      expect(details.error_message).to eq(
        "The value of 'day-of-the-week' cannot be read as the requested type (invalid-number)."
      )
    end

    it "resolves an object read of malformed JSON to the in-code default value with TYPE_MISMATCH" do
      client = open_feature_client_serving(wire_config("checkout-settings", '{"steps":', type: "json"))

      details = client.fetch_object_details(flag_key: "checkout-settings", default_value: { "steps" => 1 })

      expect(details.value).to eq("steps" => 1)
      expect(details.reason).to eq("ERROR")
      expect(details.error_code).to eq("TYPE_MISMATCH")
      expect(details.error_message).to eq(
        "The value of 'checkout-settings' cannot be read as the requested type (invalid-json)."
      )
    end

    it "resolves a boolean read of an integer config to the in-code default value with TYPE_MISMATCH" do
      client = open_feature_client_serving(wire_config("page-size", "25", type: "integer"))

      details = client.fetch_boolean_details(flag_key: "page-size", default_value: true)

      expect(details.value).to be(true)
      expect(details.reason).to eq("ERROR")
      expect(details.error_code).to eq("TYPE_MISMATCH")
      expect(details.error_message).to eq(
        "The value of 'page-size' cannot be read as the requested type (invalid-boolean)."
      )
    end
  end
end
