# frozen_string_literal: true

require_relative "../support/sdk_server_serving_the_sample_configs"

RSpec.describe ConfigDirector::Context do
  it "holds what it was built with" do
    context = described_class.new(id: "user-123", kind: "user", name: "Ada", traits: { "plan" => "pro" },
                                  anonymous: true)

    expect(context.id).to eq("user-123")
    expect(context.kind).to eq("user")
    expect(context.name).to eq("Ada")
    expect(context.traits).to eq({ "plan" => "pro" })
    expect(context.anonymous?).to be(true)
  end

  it "has no id, kind, name or traits and is not anonymous unless told otherwise" do
    context = described_class.new

    expect(context.id).to be_nil
    expect(context.kind).to be_nil
    expect(context.name).to be_nil
    expect(context.traits).to be_nil
    expect(context.anonymous?).to be(false)
  end

  it "cannot be changed once built" do
    context = described_class.new(id: "user-123", traits: { "plan" => "pro", "teams" => ["blue"] })

    expect(context).to be_frozen
    expect(context.traits).to be_frozen
    expect(context.traits.fetch("teams")).to be_frozen
  end

  it "keeps its traits when the Hash it was built from changes" do
    traits = { "plan" => "pro", "teams" => ["blue"], "address" => { "city" => "Lisbon" } }
    context = described_class.new(traits: traits)

    traits["plan"] = "free"
    traits.fetch("teams") << "red"
    traits.fetch("address")["city"] = "Porto"

    expect(context.traits).to eq({ "plan" => "pro", "teams" => ["blue"], "address" => { "city" => "Lisbon" } })
  end

  it "keeps its id, kind and name when the Strings they were built from change" do
    id = +"user-123"
    kind = +"device"
    name = +"Ada"
    context = described_class.new(id: id, kind: kind, name: name)

    id << "4"
    kind << "s"
    name << " Lovelace"

    expect(context.id).to eq("user-123")
    expect(context.kind).to eq("device")
    expect(context.name).to eq("Ada")
  end

  it "leaves the Hash it was built from as it was" do
    traits = { plan: :pro }

    described_class.new(traits: traits)

    expect(traits).to eq({ plan: :pro })
    expect(traits).not_to be_frozen
  end

  it "reads a Symbol trait key as its text" do
    expect(described_class.new(traits: { plan: "pro" }).traits).to eq({ "plan" => "pro" })
  end

  it "reads a Symbol trait value as its text" do
    expect(described_class.new(traits: { "plan" => :pro }).traits).to eq({ "plan" => "pro" })
  end

  it "reads Symbol keys and values as their text inside nested traits" do
    context = described_class.new(traits: { address: { city: :lisbon }, teams: [:blue, { role: :admin }] })

    expect(context.traits).to eq(
      { "address" => { "city" => "lisbon" }, "teams" => ["blue", { "role" => "admin" }] }
    )
  end

  it "keeps trait values that are numbers, booleans and nil" do
    context = described_class.new(traits: { "seats" => 5, "ratio" => 0.5, "trial" => false, "coupon" => nil })

    expect(context.traits).to eq({ "seats" => 5, "ratio" => 0.5, "trial" => false, "coupon" => nil })
  end

  it "reads an Integer id as its digits" do
    expect(described_class.new(id: 42).id).to eq("42")
  end

  it "raises for an id that is a Symbol" do
    expect { described_class.new(id: :user) }.to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises for an id that is a Float" do
    expect { described_class.new(id: 42.0) }.to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises for a name that is not a String" do
    expect { described_class.new(name: 42) }.to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises for traits that are not a Hash" do
    expect { described_class.new(traits: [%w[plan pro]]) }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises for an anonymous flag that is neither true nor false" do
    expect { described_class.new(anonymous: "yes") }.to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "is built with any kind" do
    expect(described_class.new(kind: "Not A Kind").kind).to eq("Not A Kind")
  end

  it "equals a context built with the same values" do
    expect(described_class.new(id: "user-123", traits: { plan: "pro" }))
      .to eq(described_class.new(id: "user-123", traits: { "plan" => "pro" }))
  end

  it "does not equal a context with another id" do
    expect(described_class.new(id: "user-123")).not_to eq(described_class.new(id: "user-124"))
  end

  it "does not equal a context of another kind" do
    expect(described_class.new(id: "user-123")).not_to eq(described_class.new(id: "user-123", kind: "device"))
  end

  it "is the same Hash key as a context built with the same values" do
    visits = { described_class.new(id: "user-123") => 1 }

    expect(visits[described_class.new(id: "user-123")]).to eq(1)
  end

  it "builds a copy with the values given to with and leaves itself as it was" do
    context = described_class.new(id: "user-123", traits: { "plan" => "pro" })

    renamed = context.with(name: "Ada")

    expect(renamed).to eq(described_class.new(id: "user-123", name: "Ada", traits: { "plan" => "pro" }))
    expect(context.name).to be_nil
  end

  it "reads the values given to with as it reads the values it is built with" do
    context = described_class.new(id: "user-123")

    expect(context.with(id: 42, traits: { plan: :pro }))
      .to eq(described_class.new(id: "42", traits: { "plan" => "pro" }))
  end

  it "raises for a value given to with that it would raise for when built" do
    expect { described_class.new(id: "user-123").with(anonymous: "yes") }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "gives its values as a Hash" do
    context = described_class.new(id: "user-123", kind: "device", name: "Ada", traits: { plan: "pro" })

    expect(context.to_h).to eq(
      { id: "user-123", kind: "device", name: "Ada", traits: { "plan" => "pro" }, anonymous: false }
    )
  end

  it "matches a pattern on its values" do
    context = described_class.new(id: "device-7", kind: "device")

    identifier = case context
                 in { kind: "device", id: String => device_id } then device_id
                 end

    expect(identifier).to eq("device-7")
  end

  it "reads whether it is anonymous only through anonymous?" do
    expect(described_class.new(anonymous: true)).not_to respond_to(:anonymous)
  end
end

RSpec.describe "A context's traits and id in targeting rules" do
  include_context "with an SDK server that serves the sample configs"

  let(:client) { client_of_the_sample_configs(logger: Logger.new(IO::NULL)).tap(&:init) }

  it "matches a targeting rule on a trait given with a Symbol key" do
    context = ConfigDirector::Context.new(traits: { plan: "pro" })

    expect(client.get_value("day-of-the-week-config", "Sunday", context)).to eq("Tuesday")
  end

  it "matches a targeting rule on a trait given as a Symbol" do
    context = ConfigDirector::Context.new(traits: { plan: :pro })

    expect(client.get_value("day-of-the-week-config", "Sunday", context)).to eq("Tuesday")
  end

  it "places a context with an Integer id in a percentage rollout" do
    evaluation = client.evaluate("temporary-feature-flag", false, ConfigDirector::Context.new(id: 42))

    expect(evaluation.value).to be(true)
    expect(evaluation.reason).to eq("found-match")
  end
end
