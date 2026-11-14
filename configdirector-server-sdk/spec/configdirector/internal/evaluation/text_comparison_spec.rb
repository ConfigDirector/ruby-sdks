# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Evaluation::TextComparison do
  it "matches text equal to the first target" do
    expect(described_class.matches?("pro", "equals", %w[pro team])).to be(true)
  end

  it "compares equals against the first target only" do
    expect(described_class.matches?("team", "equals", %w[pro team])).to be(false)
  end

  it "matches equals spelled as a symbol" do
    expect(described_class.matches?("pro", "=", ["pro"])).to be(true)
  end

  it "compares equals case-sensitively" do
    expect(described_class.matches?("Pro", "equals", ["pro"])).to be(false)
  end

  it "does not match equals with no targets" do
    expect(described_class.matches?("", "equals", [])).to be(false)
  end

  it "matches text that does not equal the first target" do
    expect(described_class.matches?("free", "does not equal", ["pro"])).to be(true)
  end

  it "matches does not equal spelled as a symbol" do
    expect(described_class.matches?("free", "!=", ["pro"])).to be(true)
  end

  it "does not match does not equal with no targets" do
    expect(described_class.matches?("pro", "does not equal", [])).to be(false)
  end

  it "matches text that is one of the targets" do
    expect(described_class.matches?("team", "is one of", %w[pro team])).to be(true)
  end

  it "does not match is one of with no targets" do
    expect(described_class.matches?("", "is one of", [])).to be(false)
  end

  it "matches text outside the targets for is not one of" do
    expect(described_class.matches?("free", "is not one of", %w[pro team])).to be(true)
  end

  it "does not match is not one of for text among the targets" do
    expect(described_class.matches?("team", "is not one of", %w[pro team])).to be(false)
  end

  it "matches is not one of with no targets" do
    expect(described_class.matches?("pro", "is not one of", [])).to be(true)
  end

  it "matches text that starts with any target" do
    expect(described_class.matches?("user-42", "starts with any of", %w[admin- user-])).to be(true)
  end

  it "does not match starts with any of with no targets" do
    expect(described_class.matches?("user-42", "starts with any of", [])).to be(false)
  end

  it "matches text without a target prefix for does not start with any of" do
    expect(described_class.matches?("guest-42", "does not start with any of", %w[admin- user-])).to be(true)
  end

  it "does not match does not start with any of for text with a target prefix" do
    expect(described_class.matches?("user-42", "does not start with any of", %w[admin- user-])).to be(false)
  end

  it "matches does not start with any of with no targets" do
    expect(described_class.matches?("user-42", "does not start with any of", [])).to be(true)
  end

  it "matches text that ends with any target" do
    expect(described_class.matches?("ann@acme.com", "ends with any of", ["@example.com", "@acme.com"])).to be(true)
  end

  it "does not match ends with any of with no targets" do
    expect(described_class.matches?("ann@acme.com", "ends with any of", [])).to be(false)
  end

  it "matches text without a target suffix for does not end with any of" do
    expect(described_class.matches?("ann@other.org", "does not end with any of", ["@example.com", "@acme.com"]))
      .to be(true)
  end

  it "does not match does not end with any of for text with a target suffix" do
    expect(described_class.matches?("ann@acme.com", "does not end with any of", ["@example.com", "@acme.com"]))
      .to be(false)
  end

  it "matches does not end with any of with no targets" do
    expect(described_class.matches?("ann@acme.com", "does not end with any of", [])).to be(true)
  end

  it "does not match a regular expression operator, which the contract removed" do
    expect(described_class.matches?("pro", "matches regex", ["pro"])).to be(false)
  end
end
