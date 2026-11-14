# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Evaluation::NumberComparison do
  it "matches a number equal to the first target" do
    expect(described_class.matches?(26, "=", ["26"])).to be(true)
  end

  it "matches a number equal to a target written with a fraction" do
    expect(described_class.matches?(26, "equals", ["26.0"])).to be(true)
  end

  it "matches a number that does not equal the first target" do
    expect(described_class.matches?(26, "!=", ["25"])).to be(true)
  end

  it "matches a number less than the target" do
    expect(described_class.matches?(25, "<", ["26"])).to be(true)
  end

  it "does not match a number less than itself" do
    expect(described_class.matches?(26, "<", ["26"])).to be(false)
  end

  it "matches a number at most the target" do
    expect(described_class.matches?(26, "<=", ["26"])).to be(true)
  end

  it "matches a number greater than the target" do
    expect(described_class.matches?(26.5, ">", ["26"])).to be(true)
  end

  it "does not match a number greater than itself" do
    expect(described_class.matches?(26, ">", ["26"])).to be(false)
  end

  it "matches a number at least the target" do
    expect(described_class.matches?(26, ">=", ["26"])).to be(true)
  end

  it "parses a number in text" do
    expect(described_class.matches?("10.5", ">", ["10"])).to be(true)
  end

  it "parses a number in text with an exponent" do
    expect(described_class.matches?("1e3", "=", ["1000"])).to be(true)
  end

  it "parses a number in text with a sign" do
    expect(described_class.matches?("-5", "<", ["0"])).to be(true)
  end

  it "parses a number in text that ends with its point" do
    expect(described_class.matches?("5.", "=", ["5"])).to be(true)
  end

  it "parses a number in text that starts with its point" do
    expect(described_class.matches?(".5", "=", ["0.5"])).to be(true)
  end

  it "parses a number in text too small for a float as zero" do
    expect(described_class.matches?("1e-999", "=", ["0"])).to be(true)
  end

  it "treats text with trailing characters as unparseable" do
    expect(described_class.matches?("26abc", "=", ["26"])).to be(false)
  end

  it "treats text with surrounding whitespace as unparseable" do
    expect(described_class.matches?(" 42 ", "=", ["42"])).to be(false)
  end

  it "treats a number followed by a second line as unparseable" do
    expect(described_class.matches?("26\nabc", "=", ["26"])).to be(false)
  end

  it "treats text with digit separators as unparseable" do
    expect(described_class.matches?("1_000", "=", ["1000"])).to be(false)
  end

  it "treats text in hexadecimal as unparseable" do
    expect(described_class.matches?("0x10", "=", ["16"])).to be(false)
  end

  it "treats text with an exponent but no digits as unparseable" do
    expect(described_class.matches?("1e", "=", ["1"])).to be(false)
  end

  it "treats a point without digits as unparseable" do
    expect(described_class.matches?(".", "!=", ["0"])).to be(true)
  end

  it "treats text spelled as infinity as unparseable" do
    expect(described_class.matches?("Infinity", ">", ["0"])).to be(false)
  end

  it "treats text beyond the float range as unparseable" do
    expect(described_class.matches?("1e999", ">", ["0"])).to be(false)
  end

  it "treats text just beyond the largest float as unparseable" do
    expect(described_class.matches?("1.7976931348623159e308", ">", ["0"])).to be(false)
  end

  it "parses text that rounds to the largest float" do
    expect(described_class.matches?("1.7976931348623158e308", ">", ["1e308"])).to be(true)
  end

  it "treats an infinite float as unparseable" do
    expect(described_class.matches?(Float::INFINITY, ">", ["0"])).to be(false)
  end

  it "treats empty text as unparseable" do
    expect(described_class.matches?("", "=", ["0"])).to be(false)
  end

  it "treats an absent value as unparseable" do
    expect(described_class.matches?(nil, "<", ["10"])).to be(false)
  end

  it "treats a boolean as unparseable" do
    expect(described_class.matches?(true, "=", ["1"])).to be(false)
  end

  it "treats an array as unparseable" do
    expect(described_class.matches?(["26"], "=", ["26"])).to be(false)
  end

  it "matches an unparseable value against does not equal" do
    expect(described_class.matches?("abc", "!=", ["26"])).to be(true)
  end

  it "matches an unparseable value against does not equal spelled out" do
    expect(described_class.matches?(nil, "does not equal", ["26"])).to be(true)
  end

  it "matches an unparseable value against does not equal even with no targets" do
    expect(described_class.matches?("abc", "!=", [])).to be(true)
  end

  it "does not match a number with no targets" do
    expect(described_class.matches?(26, "!=", [])).to be(false)
  end

  it "does not match a number against an unparseable target" do
    expect(described_class.matches?(26, "!=", ["abc"])).to be(false)
  end

  it "does not match a number with an operator of another target type" do
    expect(described_class.matches?(26, "is one of", ["26"])).to be(false)
  end
end
