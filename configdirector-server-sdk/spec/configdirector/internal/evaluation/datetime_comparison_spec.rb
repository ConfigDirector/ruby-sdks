# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Evaluation::DatetimeComparison do
  instant = "2026-01-28T01:25:00.000Z"

  it "matches a datetime before a later target" do
    expect(described_class.matches?("2026-01-28T01:24:59.999Z", "is before", [instant])).to be(true)
  end

  it "does not match a datetime before itself" do
    expect(described_class.matches?(instant, "is before", [instant])).to be(false)
  end

  it "matches a datetime after an earlier target" do
    expect(described_class.matches?("2026-01-28T01:25:00.001Z", "is after", [instant])).to be(true)
  end

  it "does not match a datetime after itself" do
    expect(described_class.matches?(instant, "is after", [instant])).to be(false)
  end

  it "reads a bare year as the first moment of that year in UTC" do
    expect(described_class.matches?("2026", "is before", ["2026-01-01T00:00:00Z"])).to be(false)
  end

  it "reads a bare year as before the first millisecond of that year" do
    expect(described_class.matches?("2026", "is before", ["2026-01-01T00:00:00.001Z"])).to be(true)
  end

  it "reads a year and month as the first of the month" do
    expect(described_class.matches?("2026-01", "is before", ["2026-01-01T00:00:01Z"])).to be(true)
  end

  it "reads a date as midnight in UTC" do
    expect(described_class.matches?("2026-01-28", "is after", ["2026-01-28T00:00:00Z"])).to be(false)
  end

  it "reads a datetime without an offset as UTC" do
    expect(described_class.matches?("2026-01-28T01:25:00.001", "is after", [instant])).to be(true)
  end

  it "reads a datetime without seconds at the start of the minute" do
    expect(described_class.matches?("2026-01-28T01:24", "is before", ["2026-01-28T01:24:00.001Z"])).to be(true)
  end

  it "reads a datetime ahead of UTC as earlier than the same clock time in UTC" do
    expect(described_class.matches?("2026-01-28T01:25:00+02:00", "is before", [instant])).to be(true)
  end

  it "reads a datetime behind UTC as later than the same clock time in UTC" do
    expect(described_class.matches?("2026-01-28T01:25:00-02:00", "is after", [instant])).to be(true)
  end

  it "truncates digits beyond milliseconds" do
    expect(described_class.matches?("2026-01-28T01:25:00.123999Z", "is after", ["2026-01-28T01:25:00.123Z"]))
      .to be(false)
  end

  it "treats an impossible day as unparseable" do
    expect(described_class.matches?("2026-02-30", "is after", [instant])).to be(false)
  end

  it "parses a leap day" do
    expect(described_class.matches?("2024-02-29", "is before", [instant])).to be(true)
  end

  it "treats a leap day outside a leap year as unparseable" do
    expect(described_class.matches?("2025-02-29", "is before", [instant])).to be(false)
  end

  it "treats an impossible month as unparseable" do
    expect(described_class.matches?("2026-13-01", "is after", [instant])).to be(false)
  end

  it "treats an impossible hour as unparseable" do
    expect(described_class.matches?("2026-01-28T24:00", "is after", [instant])).to be(false)
  end

  it "treats an impossible minute as unparseable" do
    expect(described_class.matches?("2026-01-28T01:60", "is after", [instant])).to be(false)
  end

  it "treats an impossible second as unparseable" do
    expect(described_class.matches?("2026-01-28T01:25:60", "is after", [instant])).to be(false)
  end

  it "treats a date followed by a second line as unparseable" do
    expect(described_class.matches?("2026-01-28\ngarbage", "is before", [instant])).to be(false)
  end

  it "treats garbage as unparseable" do
    expect(described_class.matches?("garbage", "is before", [instant])).to be(false)
  end

  it "treats an empty value as unparseable" do
    expect(described_class.matches?("", "is before", [instant])).to be(false)
  end

  it "does not match against an unparseable target" do
    expect(described_class.matches?("2026-01-28", "is before", ["garbage"])).to be(false)
  end

  it "does not match with no targets" do
    expect(described_class.matches?("2026-01-28", "is before", [])).to be(false)
  end

  it "does not match with an operator of another target type" do
    expect(described_class.matches?("2026-01-28", "<", [instant])).to be(false)
  end
end
