# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Telemetry::AggregatedWireEntries do
  let(:counted_since) { Time.utc(2026, 11, 15, 10, 30) }
  let(:counted_until) { Time.utc(2026, 11, 15, 10, 31) }

  it "writes each event with its count and the time it was counted over" do
    wire_entries = described_class.of(
      { { reason: "invalid-context-kind" } => 7 }, counted_since: counted_since, counted_until: counted_until
    )

    expect(wire_entries).to eq(
      [{
        startTime: "2026-11-15T10:30:00.000Z", endTime: "2026-11-15T10:31:00.000Z", count: 7,
        event: { reason: "invalid-context-kind" }
      }]
    )
  end

  it "writes a count larger than the SDK server reads as the largest it reads" do
    counts_by_wire_event = { { reason: "invalid-context-kind" } => 2_147_483_648 }

    wire_entries = described_class.of(counts_by_wire_event, counted_since: counted_since, counted_until: counted_until)

    expect(wire_entries.map { |wire_entry| wire_entry.fetch(:count) }).to eq([2_147_483_647])
  end
end
