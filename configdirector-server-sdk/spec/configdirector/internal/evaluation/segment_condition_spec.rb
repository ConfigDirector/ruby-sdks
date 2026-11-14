# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Evaluation::SegmentCondition do
  segment = ConfigDirector::Internal::Evaluation::Segment
  attribute_condition = ConfigDirector::Internal::Evaluation::AttributeCondition
  acme_segment_id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  missing_segment_id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

  context_with = lambda do |**fields|
    ConfigDirector::Internal::Evaluation::EvaluationContext.new(
      identifier: nil, kind: nil, name: nil, traits: {}, app_name: nil, app_version: nil, **fields
    )
  end
  email_ends_with = lambda do |domain|
    attribute_condition.new(
      attribute: "traits", trait: "/email", operator: "ends with any of", target_type: "text", target_values: [domain]
    )
  end
  plan_is = lambda do |plan|
    attribute_condition.new(
      attribute: "traits", trait: "/plan", operator: "equals", target_type: "text", target_values: [plan]
    )
  end
  acme_employees = { acme_segment_id => segment.new(condition_groups: [[email_ends_with.call("@acme.com")]]) }
  context_with_email = ->(email) { context_with.call(traits: { "email" => email }) }

  it "holds in for a context in the segment" do
    condition = described_class.new(operator: "in", segment_id: acme_segment_id)

    expect(condition.holds_for?(context_with_email.call("ann@acme.com"), acme_employees)).to be(true)
  end

  it "does not hold in for a context outside the segment" do
    condition = described_class.new(operator: "in", segment_id: acme_segment_id)

    expect(condition.holds_for?(context_with_email.call("bob@example.com"), acme_employees)).to be(false)
  end

  it "holds not in for a context outside the segment" do
    condition = described_class.new(operator: "not in", segment_id: acme_segment_id)

    expect(condition.holds_for?(context_with_email.call("bob@example.com"), acme_employees)).to be(true)
  end

  it "does not hold not in for a context in the segment" do
    condition = described_class.new(operator: "not in", segment_id: acme_segment_id)

    expect(condition.holds_for?(context_with_email.call("ann@acme.com"), acme_employees)).to be(false)
  end

  it "matches segment operators case-insensitively" do
    condition = described_class.new(operator: "Not In", segment_id: acme_segment_id)

    expect(condition.holds_for?(context_with_email.call("bob@example.com"), acme_employees)).to be(true)
  end

  it "never holds an unknown segment operator" do
    condition = described_class.new(operator: "equals", segment_id: acme_segment_id)

    expect(condition.holds_for?(context_with_email.call("ann@acme.com"), acme_employees)).to be(false)
  end

  it "does not hold in a missing segment" do
    condition = described_class.new(operator: "in", segment_id: missing_segment_id)

    expect(condition.holds_for?(context_with_email.call("ann@acme.com"), acme_employees)).to be(false)
  end

  it "does not hold not in a missing segment" do
    condition = described_class.new(operator: "not in", segment_id: missing_segment_id)

    expect(condition.holds_for?(context_with_email.call("ann@acme.com"), acme_employees)).to be(false)
  end

  it "does not hold not in a segment when the payload has no segments" do
    condition = described_class.new(operator: "not in", segment_id: acme_segment_id)

    expect(condition.holds_for?(context_with_email.call("ann@acme.com"), {})).to be(false)
  end

  it "places a context in a segment when a later group matches" do
    condition = described_class.new(operator: "in", segment_id: acme_segment_id)
    segments = {
      acme_segment_id => segment.new(condition_groups: [[plan_is.call("pro")], [email_ends_with.call("@acme.com")]])
    }

    expect(condition.holds_for?(context_with_email.call("ann@acme.com"), segments)).to be(true)
  end

  it "matches a group when every condition holds" do
    condition = described_class.new(operator: "in", segment_id: acme_segment_id)
    segments = {
      acme_segment_id => segment.new(condition_groups: [[plan_is.call("pro"), email_ends_with.call("@acme.com")]])
    }
    context = context_with.call(traits: { "plan" => "pro", "email" => "ann@acme.com" })

    expect(condition.holds_for?(context, segments)).to be(true)
  end

  it "does not match a group when one condition fails" do
    condition = described_class.new(operator: "in", segment_id: acme_segment_id)
    segments = {
      acme_segment_id => segment.new(condition_groups: [[plan_is.call("pro"), email_ends_with.call("@acme.com")]])
    }
    context = context_with.call(traits: { "plan" => "pro", "email" => "ann@example.com" })

    expect(condition.holds_for?(context, segments)).to be(false)
  end

  it "compares an absent trait as empty text inside a group" do
    condition = described_class.new(operator: "in", segment_id: acme_segment_id)
    not_on_the_free_plan = attribute_condition.new(
      attribute: "traits", trait: "/plan", operator: "is not one of", target_type: "text", target_values: ["free"]
    )
    segments = { acme_segment_id => segment.new(condition_groups: [[not_on_the_free_plan]]) }

    expect(condition.holds_for?(context_with.call, segments)).to be(true)
  end

  it "matches every context with a group without conditions" do
    condition = described_class.new(operator: "in", segment_id: acme_segment_id)
    segments = { acme_segment_id => segment.new(condition_groups: [[]]) }

    expect(condition.holds_for?(context_with.call, segments)).to be(true)
  end

  it "holds no context in a segment without groups" do
    condition = described_class.new(operator: "in", segment_id: acme_segment_id)
    segments = { acme_segment_id => segment.new(condition_groups: []) }

    expect(condition.holds_for?(context_with_email.call("ann@acme.com"), segments)).to be(false)
  end

  it "holds not in a segment without groups for every context" do
    condition = described_class.new(operator: "not in", segment_id: acme_segment_id)
    segments = { acme_segment_id => segment.new(condition_groups: []) }

    expect(condition.holds_for?(context_with_email.call("ann@acme.com"), segments)).to be(true)
  end
end
