# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Evaluation::SemverComparison do
  it "matches a version equal to the first target" do
    expect(described_class.matches?("1.2.3", "=", ["1.2.3"])).to be(true)
  end

  it "coerces a version missing its minor and patch to zeros" do
    expect(described_class.matches?("1", "=", ["1.0.0"])).to be(true)
  end

  it "coerces a version missing its patch to zero" do
    expect(described_class.matches?("1.0", "=", ["1.0.0"])).to be(true)
  end

  it "coerces a version with a leading prefix" do
    expect(described_class.matches?("v2.3.4", "=", ["2.3.4"])).to be(true)
  end

  it "drops a fourth component" do
    expect(described_class.matches?("1.2.3.4", "=", ["1.2.3"])).to be(true)
  end

  it "drops a prerelease suffix" do
    expect(described_class.matches?("0.1.645-a", "=", ["0.1.645"])).to be(true)
  end

  it "compares majors numerically" do
    expect(described_class.matches?("10.0.0", ">", ["9.0.0"])).to be(true)
  end

  it "compares minors when the majors are equal" do
    expect(described_class.matches?("1.10.0", ">", ["1.9.0"])).to be(true)
  end

  it "compares patches when the majors and minors are equal" do
    expect(described_class.matches?("1.2.10", ">", ["1.2.9"])).to be(true)
  end

  it "matches a version less than the target" do
    expect(described_class.matches?("1.2.3", "<", ["1.3.0"])).to be(true)
  end

  it "does not match a version less than itself" do
    expect(described_class.matches?("1.2.3", "<", ["1.2.3"])).to be(false)
  end

  it "matches a version at most the target" do
    expect(described_class.matches?("1.2.3", "<=", ["1.2.3"])).to be(true)
  end

  it "does not match a version greater than itself" do
    expect(described_class.matches?("1.2.3", ">", ["1.2.3"])).to be(false)
  end

  it "matches a version at least the target" do
    expect(described_class.matches?("1.2.3", ">=", ["1.2.3"])).to be(true)
  end

  it "matches a version that is one of the targets" do
    expect(described_class.matches?("1.0", "is one of", ["2.0.0", "1.0.0"])).to be(true)
  end

  it "matches a version outside the targets for is not one of" do
    expect(described_class.matches?("3.0", "is not one of", ["2.0.0", "1.0.0"])).to be(true)
  end

  it "does not match is not one of for a version among the targets" do
    expect(described_class.matches?("1.0", "is not one of", ["2.0.0", "1.0.0"])).to be(false)
  end

  it "matches is not one of with no targets" do
    expect(described_class.matches?("1.0.0", "is not one of", [])).to be(true)
  end

  it "does not match equals with no targets" do
    expect(described_class.matches?("1.0.0", "=", [])).to be(false)
  end

  it "matches a blank version against is not one of" do
    expect(described_class.matches?("   ", "is not one of", ["1.0.0"])).to be(true)
  end

  it "does not order an empty version before any target" do
    expect(described_class.matches?("", "<", ["1.0.0"])).to be(false)
  end

  it "never equals a target with a version that cannot be coerced" do
    expect(described_class.matches?("abc", "=", ["abc"])).to be(false)
  end

  it "never orders a version that cannot be coerced" do
    expect(described_class.matches?("abc", "<", ["1.0.0"])).to be(false)
  end

  it "matches a version that cannot be coerced against is not one of" do
    expect(described_class.matches?("abc", "is not one of", ["abc"])).to be(true)
  end

  it "never orders against a target that cannot be coerced" do
    expect(described_class.matches?("1.0.0", ">", ["abc"])).to be(false)
  end

  it "keeps a major of sixteen digits" do
    expect(described_class.matches?("1234567890123456.0.0", ">", ["1.0.0"])).to be(true)
  end

  it "does not read seventeen digits as a major" do
    expect(described_class.matches?("12345678901234567.0.0", ">", ["1.0.0"])).to be(false)
  end

  it "does not match a version with an operator of another target type" do
    expect(described_class.matches?("1.0.0", "!=", ["2.0.0"])).to be(false)
  end
end
