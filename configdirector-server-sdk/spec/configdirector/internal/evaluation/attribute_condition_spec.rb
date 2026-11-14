# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Evaluation::AttributeCondition do
  context_with = lambda do |**fields|
    ConfigDirector::Internal::Evaluation::EvaluationContext.new(
      identifier: nil, kind: nil, name: nil, traits: {}, app_name: nil, app_version: nil, **fields
    )
  end

  text_condition = lambda do |attribute, trait, operator, *target_values|
    described_class.new(
      attribute: attribute, trait: trait, operator: operator, target_type: "text", target_values: target_values
    )
  end

  it "compares an identifier condition against the context's identifier" do
    condition = text_condition.call("identifier", nil, "equals", "u1")

    expect(condition.holds_for?(context_with.call(identifier: "u1"), {})).to be(true)
  end

  it "does not hold an identifier condition for another identifier" do
    condition = text_condition.call("identifier", nil, "equals", "u1")

    expect(condition.holds_for?(context_with.call(identifier: "u2"), {})).to be(false)
  end

  it "compares a name condition against the context's name" do
    condition = text_condition.call("name", nil, "equals", "ann")

    expect(condition.holds_for?(context_with.call(name: "ann"), {})).to be(true)
  end

  it "compares an app name condition against the application's name" do
    condition = text_condition.call("appName", nil, "equals", "shop")

    expect(condition.holds_for?(context_with.call(app_name: "shop"), {})).to be(true)
  end

  it "compares an app version condition against the application's version" do
    condition = described_class.new(
      attribute: "appVersion", trait: nil, operator: ">=", target_type: "semver", target_values: ["2.0.0"]
    )

    expect(condition.holds_for?(context_with.call(app_version: "v2.3.4"), {})).to be(true)
  end

  it "reads a traits condition's trait at its pointer" do
    condition = text_condition.call("traits", "/team/name", "equals", "core")

    expect(condition.holds_for?(context_with.call(traits: { "team" => { "name" => "core" } }), {})).to be(true)
  end

  it "compares a traits condition without a pointer as empty text" do
    condition = text_condition.call("traits", nil, "equals", "")

    expect(condition.holds_for?(context_with.call(traits: { "plan" => "pro" }), {})).to be(true)
  end

  it "compares a traits condition with an empty pointer as empty text" do
    condition = text_condition.call("traits", "", "equals", "")

    expect(condition.holds_for?(context_with.call(traits: { "" => "pro" }), {})).to be(true)
  end

  it "compares an absent trait as empty text, so a negated operator holds" do
    condition = text_condition.call("traits", "/plan", "is not one of", "free")

    expect(condition.holds_for?(context_with.call, {})).to be(true)
  end

  it "compares a null trait as empty text" do
    condition = text_condition.call("traits", "/plan", "equals", "")

    expect(condition.holds_for?(context_with.call(traits: { "plan" => nil }), {})).to be(true)
  end

  it "compares an absent identifier as empty text" do
    condition = text_condition.call("identifier", nil, "does not equal", "u1")

    expect(condition.holds_for?(context_with.call, {})).to be(true)
  end

  it "never holds a condition on an unknown attribute" do
    condition = text_condition.call("email", nil, "is not one of")

    expect(condition.holds_for?(context_with.call, {})).to be(false)
  end

  it "never holds a condition of an unknown target type" do
    condition = described_class.new(
      attribute: "identifier", trait: nil, operator: "equals", target_type: "uuid", target_values: ["u1"]
    )

    expect(condition.holds_for?(context_with.call(identifier: "u1"), {})).to be(false)
  end

  it "matches a text operator case-insensitively" do
    condition = text_condition.call("identifier", nil, "Is NOT One Of", "u2")

    expect(condition.holds_for?(context_with.call(identifier: "u1"), {})).to be(true)
  end

  it "matches a datetime operator case-insensitively" do
    condition = described_class.new(
      attribute: "traits", trait: "/joined", operator: "Is Before", target_type: "datetime",
      target_values: ["2026-01-28"]
    )

    expect(condition.holds_for?(context_with.call(traits: { "joined" => "2025-12-31" }), {})).to be(true)
  end

  it "compares a true trait as the text true" do
    condition = text_condition.call("traits", "/beta", "equals", "true")

    expect(condition.holds_for?(context_with.call(traits: { "beta" => true }), {})).to be(true)
  end

  it "compares a false trait as the text false" do
    condition = text_condition.call("traits", "/beta", "equals", "false")

    expect(condition.holds_for?(context_with.call(traits: { "beta" => false }), {})).to be(true)
  end

  it "compares an integer trait as its digits in text" do
    condition = text_condition.call("traits", "/seats", "equals", "26")

    expect(condition.holds_for?(context_with.call(traits: { "seats" => 26 }), {})).to be(true)
  end

  it "compares a whole float trait as its digits in text" do
    condition = text_condition.call("traits", "/seats", "equals", "26")

    expect(condition.holds_for?(context_with.call(traits: { "seats" => 26.0 }), {})).to be(true)
  end

  it "compares a fractional trait as its JSON text in text" do
    condition = text_condition.call("traits", "/ratio", "equals", "26.5")

    expect(condition.holds_for?(context_with.call(traits: { "ratio" => 26.5 }), {})).to be(true)
  end

  it "compares a numeric trait as a number" do
    condition = described_class.new(
      attribute: "traits", trait: "/seats", operator: ">", target_type: "number", target_values: ["10"]
    )

    expect(condition.holds_for?(context_with.call(traits: { "seats" => 26 }), {})).to be(true)
  end

  it "holds does not equal any number for an absent trait" do
    condition = described_class.new(
      attribute: "traits", trait: "/seats", operator: "!=", target_type: "number", target_values: ["10"]
    )

    expect(condition.holds_for?(context_with.call, {})).to be(true)
  end

  it "compares a structured trait as empty text" do
    condition = text_condition.call("traits", "/tags", "equals", "")

    expect(condition.holds_for?(context_with.call(traits: { "tags" => ["a"] }), {})).to be(true)
  end

  it "compares an array trait's elements" do
    condition = described_class.new(
      attribute: "traits", trait: "/tags", operator: "contains any of", target_type: "array", target_values: ["blue"]
    )

    expect(condition.holds_for?(context_with.call(traits: { "tags" => %w[red blue] }), {})).to be(true)
  end

  it "compares a datetime trait as an instant" do
    condition = described_class.new(
      attribute: "traits", trait: "/joined", operator: "is before", target_type: "datetime",
      target_values: ["2026-01-28"]
    )

    expect(condition.holds_for?(context_with.call(traits: { "joined" => "2025-12-31" }), {})).to be(true)
  end

  it "compares a kind condition against the context's kind" do
    condition = text_condition.call("kind", nil, "is one of", "device", "tenant")

    expect(condition.holds_for?(context_with.call(kind: "device"), {})).to be(true)
  end

  it "does not hold a kind condition for another kind" do
    condition = text_condition.call("kind", nil, "is one of", "device", "tenant")

    expect(condition.holds_for?(context_with.call(kind: "organization"), {})).to be(false)
  end

  it "compares an omitted kind as user" do
    condition = text_condition.call("kind", nil, "equals", "user")

    expect(condition.holds_for?(context_with.call, {})).to be(true)
  end

  it "holds is not one of a device for a context without a kind" do
    condition = text_condition.call("kind", nil, "is NOT one of", "device")

    expect(condition.holds_for?(context_with.call, {})).to be(true)
  end

  it "holds does not equal user for a kind other than user" do
    condition = text_condition.call("kind", nil, "does not equal", "user")

    expect(condition.holds_for?(context_with.call(kind: "tenant"), {})).to be(true)
  end

  it "reads a trait named kind as an ordinary trait" do
    condition = text_condition.call("traits", "/kind", "equals", "robot")

    expect(condition.holds_for?(context_with.call(kind: "device", traits: { "kind" => "robot" }), {}))
      .to be(true)
  end

  it "ignores a trait named kind in a kind condition" do
    condition = text_condition.call("kind", nil, "equals", "robot")

    expect(condition.holds_for?(context_with.call(kind: "device", traits: { "kind" => "robot" }), {}))
      .to be(false)
  end
end
