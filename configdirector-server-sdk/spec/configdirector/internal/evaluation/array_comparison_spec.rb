# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Evaluation::ArrayComparison do
  it "matches an array that contains any target" do
    expect(described_class.matches?(%w[red blue], "contains any of", %w[green blue])).to be(true)
  end

  it "does not match an array without a target for contains any of" do
    expect(described_class.matches?(["red"], "contains any of", %w[green blue])).to be(false)
  end

  it "matches an array without a target for does not contain any of" do
    expect(described_class.matches?(["red"], "does not contain any of", %w[green blue])).to be(true)
  end

  it "does not match does not contain any of for an array holding a target" do
    expect(described_class.matches?(%w[red blue], "does not contain any of", ["blue"])).to be(false)
  end

  it "compares numeric elements by their text" do
    expect(described_class.matches?([1, 2], "contains any of", ["1"])).to be(true)
  end

  it "compares boolean elements by their text" do
    expect(described_class.matches?([true], "contains any of", ["true"])).to be(true)
  end

  it "compares elements case-sensitively" do
    expect(described_class.matches?(["BLUE"], "contains any of", ["blue"])).to be(false)
  end

  it "drops elements without a text form" do
    expect(described_class.matches?([nil, [], { "k" => "v" }], "contains any of", [""])).to be(false)
  end

  it "matches does not contain any of for an array of elements without a text form" do
    expect(described_class.matches?([nil], "does not contain any of", [""])).to be(true)
  end

  it "does not match contains any of with no targets" do
    expect(described_class.matches?(["red"], "contains any of", [])).to be(false)
  end

  it "matches does not contain any of with no targets" do
    expect(described_class.matches?(["red"], "does not contain any of", [])).to be(true)
  end

  it "finds nothing in a scalar value" do
    expect(described_class.matches?("red", "contains any of", ["red"])).to be(false)
  end

  it "matches does not contain any of for a scalar value" do
    expect(described_class.matches?("red", "does not contain any of", ["red"])).to be(true)
  end

  it "finds nothing in an object" do
    expect(described_class.matches?({ "color" => "red" }, "contains any of", ["red"])).to be(false)
  end

  it "finds nothing in an absent value" do
    expect(described_class.matches?(nil, "contains any of", [""])).to be(false)
  end

  it "does not match with an operator of another target type" do
    expect(described_class.matches?(["red"], "is one of", ["red"])).to be(false)
  end
end
