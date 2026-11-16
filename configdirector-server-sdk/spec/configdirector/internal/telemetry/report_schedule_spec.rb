# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Telemetry::ReportSchedule do
  let(:schedule) do
    described_class.new(
      ConfigDirector::Internal::Telemetry::ReportTiming.new(
        seconds_before_the_first_report: 0.05, seconds_between_reports: 0.05, seconds_a_report_may_take: 1
      )
    )
  end

  after { schedule.stop }

  def telemetry_threads_alive
    Thread.list.count { |thread| thread.alive? && thread.name == "configdirector-telemetry" }
  end

  it "starts no second thread while its thread is alive" do
    schedule.start { nil }

    schedule.start { nil }

    expect(telemetry_threads_alive).to eq(1)
  end

  it "ends its thread when it is stopped" do
    schedule.start { nil }

    schedule.stop
    schedule.wait_for_a_report_being_sent

    expect(telemetry_threads_alive).to eq(0)
  end

  it "sends a report after each interval until it is stopped" do
    reports_sent = Queue.new
    schedule.start { reports_sent << :report }

    first_report = reports_sent.pop(timeout: 2)
    second_report = reports_sent.pop(timeout: 2)
    schedule.stop
    schedule.wait_for_a_report_being_sent
    reports_sent.clear

    expect([first_report, second_report]).to eq(%i[report report])
    expect(reports_sent.pop(timeout: 0.2)).to be_nil
  end
end
