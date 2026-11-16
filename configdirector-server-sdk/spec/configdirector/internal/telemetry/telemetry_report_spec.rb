# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Telemetry::TelemetryReport do
  def report_that_dropped(evaluations_dropped:, captured_contexts_dropped:)
    described_class.new(
      evaluations: [], evaluations_collected_since: nil, evaluations_dropped: evaluations_dropped,
      captured_contexts: [], captured_contexts_dropped: captured_contexts_dropped, invalid_context_wire_entries: [],
      tracked_events: [], taken_at: Time.utc(2026, 11, 15, 10, 30)
    )
  end

  it "writes the counts of what it dropped" do
    report = report_that_dropped(evaluations_dropped: 12, captured_contexts_dropped: 3)

    expect(report.wire_events.fetch(:droppedEvents)).to eq({ evaluatedConfig: 12, capturedContexts: 3 })
  end

  it "writes a count larger than the SDK server reads as the largest it reads" do
    report = report_that_dropped(evaluations_dropped: 2_147_483_648, captured_contexts_dropped: 5_000_000_000)

    expect(report.wire_events.fetch(:droppedEvents)).to eq(
      { evaluatedConfig: 2_147_483_647, capturedContexts: 2_147_483_647 }
    )
  end
end
