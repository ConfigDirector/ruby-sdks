# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Evaluation::ScalarText do
  it "renders a string as itself" do
    expect(described_class.of("abc")).to eq("abc")
  end

  it "renders true as its JSON spelling" do
    expect(described_class.of(true)).to eq("true")
  end

  it "renders false as its JSON spelling" do
    expect(described_class.of(false)).to eq("false")
  end

  it "renders an integer as its digits" do
    expect(described_class.of(26)).to eq("26")
  end

  it "renders a negative integer with its sign" do
    expect(described_class.of(-3)).to eq("-3")
  end

  it "renders a whole float without a fraction" do
    expect(described_class.of(26.0)).to eq("26")
  end

  it "renders a fractional number with its fraction" do
    expect(described_class.of(26.5)).to eq("26.5")
  end

  it "renders a negative float with its sign" do
    expect(described_class.of(-0.25)).to eq("-0.25")
  end

  it "renders negative zero as zero" do
    expect(described_class.of(-0.0)).to eq("0")
  end

  it "renders a fractional number with every digit it needs to read back the same" do
    expect(described_class.of(0.30000000000000004)).to eq("0.30000000000000004")
  end

  it "renders a large fractional number without an exponent" do
    expect(described_class.of(1_234_567.5)).to eq("1234567.5")
  end

  it "spells out a large whole float" do
    expect(described_class.of(1e20)).to eq("100000000000000000000")
  end

  it "gives null no text" do
    expect(described_class.of(nil)).to be_nil
  end

  it "gives an array no text" do
    expect(described_class.of(["a"])).to be_nil
  end

  it "gives an object no text" do
    expect(described_class.of({ "a" => "b" })).to be_nil
  end
end
