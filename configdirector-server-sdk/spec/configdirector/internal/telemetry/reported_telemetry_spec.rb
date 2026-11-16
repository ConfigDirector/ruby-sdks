# frozen_string_literal: true

require_relative "../../../support/elapsed_seconds"
require_relative "../../../support/recording_logger"
require_relative "../../../support/scripted_sdk_server"
require_relative "../../../support/waiting"

RSpec.describe ConfigDirector::Internal::Telemetry::ReportedTelemetry do
  include ElapsedSeconds

  let(:sdk_server) { ScriptedSdkServer.new }
  let(:logger) { RecordingLogger.new }
  let(:telemetries_created) { [] }

  before { sdk_server.hold_telemetry_reports }

  after do
    sdk_server.stop
    telemetries_created.each(&:close)
  end

  def telemetry_reporting(seconds_before_the_first_report: 0.05, seconds_between_reports: 0.05,
                          seconds_a_report_may_take: 5)
    telemetry_reporting_to(
      sdk_server.url,
      ConfigDirector::Internal::Telemetry::ReportTiming.new(
        seconds_before_the_first_report: seconds_before_the_first_report,
        seconds_between_reports: seconds_between_reports, seconds_a_report_may_take: seconds_a_report_may_take
      )
    )
  end

  def telemetry_reporting_to(url, timing)
    telemetry = described_class.reporting_to(
      url: url, server_sdk_key: "server-sdk-key", metadata: ConfigDirector::Metadata.new,
      sdk_identity: ConfigDirector::Internal::Identity::SdkIdentity.of_the_server_sdk, event_queue_limit: 5_000,
      timing: timing, logger: logger
    )
    telemetries_created << telemetry
    telemetry
  end

  def read_of(config_key, context: nil)
    ConfigDirector::Internal::Client::ConfigRead.new(
      config_key: config_key, context: context,
      in_code_default_value: ConfigDirector::Internal::Value::InCodeDefaultValue.from("Sunday")
    ).evaluated_to_the_in_code_default_value("config-state-missing", nil)
  end

  def config_keys_reported_in(telemetry_request)
    telemetry_request.json.fetch("aggregatedEvents").fetch("evaluatedConfig").map do |evaluation|
      evaluation.fetch("event").fetch("key")
    end
  end

  def no_report_arrives_within?(seconds)
    !sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: seconds)
  end

  describe "on its schedule" do
    it "sends the first report after the wait before it, and the next one an interval after the first ended" do
      telemetry = telemetry_reporting(seconds_before_the_first_report: 0.4, seconds_between_reports: 0.8)
      telemetry.record(read_of("read-before-the-first-report"))
      first_request = nil
      second_request = nil

      seconds_before_the_first_report = seconds_taken do
        telemetry.start_reporting
        first_request = sdk_server.next_telemetry_request
      end
      telemetry.record(read_of("read-before-the-second-report"))
      first_request.answer(status: 204)
      seconds_between_the_reports = seconds_taken { second_request = sdk_server.next_telemetry_request }

      expect(seconds_before_the_first_report).to be_between(0.35, 0.75)
      expect(config_keys_reported_in(first_request)).to eq(["read-before-the-first-report"])
      expect(seconds_between_the_reports).to be_between(0.75, 1.5)
      expect(config_keys_reported_in(second_request)).to eq(["read-before-the-second-report"])
    end

    it "sends nothing before it is started" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("day-of-the-week"))

      expect(no_report_arrives_within?(0.3)).to be(true)
    end

    it "sends nothing while nothing was collected" do
      telemetry = telemetry_reporting
      telemetry.start_reporting

      expect(no_report_arrives_within?(0.3)).to be(true)
    end
  end

  describe "when the SDK server answers 401" do
    it "sends no further report and logs one warning" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-before-the-refusal"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request.answer(status: 401)

      telemetry.record(read_of("read-after-the-refusal"))

      expect(no_report_arrives_within?(0.4)).to be(true)
      expect(logger.messages_at(:warn)).to eq(
        [
          "[EventReporter] Received a fatal status response (401) from the telemetry endpoint. " \
          "No more telemetry data will be sent."
        ]
      )
    end

    it "sends no last report when it is closed" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-before-the-refusal"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request.answer(status: 401)
      Waiting.wait_up_to(2) { logger.messages_at(:warn).any? }
      telemetry.record(read_of("read-after-the-refusal"))

      telemetry.close

      expect(no_report_arrives_within?(0)).to be(true)
    end

    it "ends its thread" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-before-the-refusal"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request.answer(status: 401)

      Waiting.wait_up_to(2) { Thread.list.none? { |thread| thread.name == "configdirector-telemetry" } }

      expect(Thread.list.map(&:name)).not_to include("configdirector-telemetry")
    end
  end

  describe "when it is started again after a refusal" do
    it "sends no report" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-before-the-refusal"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request.answer(status: 401)
      Waiting.wait_up_to(2) { logger.messages_at(:warn).any? }

      telemetry.start_reporting
      telemetry.record(read_of("read-after-the-refusal"))

      expect(no_report_arrives_within?(0.4)).to be(true)
    end
  end

  describe "in a forked process, after a refusal" do
    it "starts no thread" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-before-the-refusal"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request.answer(status: 401)
      Waiting.wait_up_to(2) { Thread.list.none? { |thread| thread.name == "configdirector-telemetry" } }

      telemetry.restart_in_a_forked_process(:fork)

      expect(Thread.list.map(&:name)).not_to include("configdirector-telemetry")
    end
  end

  describe "when the SDK server answers 404" do
    it "sends no further report" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-before-the-refusal"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request.answer(status: 404)

      telemetry.record(read_of("read-after-the-refusal"))

      expect(no_report_arrives_within?(0.4)).to be(true)
    end
  end

  describe "when the SDK server answers 413" do
    it "discards that report, logs one warning and sends the next report without counting dropped events" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-in-the-report-that-was-too-large"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request.answer(status: 413)

      telemetry.record(read_of("read-in-the-next-report"))
      next_request = sdk_server.next_telemetry_request

      expect(config_keys_reported_in(next_request)).to eq(["read-in-the-next-report"])
      expect(next_request.json.fetch("droppedEvents")).to eq("evaluatedConfig" => 0, "capturedContexts" => 0)
      expect(logger.messages_at(:warn)).to eq(
        [
          "[EventReporter] The telemetry endpoint responded with status 413. " \
          "The events in this report were discarded."
        ]
      )
    end
  end

  describe "when the SDK server answers 429" do
    it "discards that report, logs one warning and sends the next report" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-in-the-report-that-was-throttled"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request.answer(status: 429)

      telemetry.record(read_of("read-in-the-next-report"))

      expect(config_keys_reported_in(sdk_server.next_telemetry_request)).to eq(["read-in-the-next-report"])
      expect(logger.messages_at(:warn)).to eq(
        [
          "[EventReporter] The telemetry endpoint responded with status 429. " \
          "The events in this report were discarded."
        ]
      )
    end
  end

  describe "when the SDK server answers 500" do
    it "discards that report, logs one warning and sends the next report" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-in-the-report-that-failed"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request.answer(status: 500)

      telemetry.record(read_of("read-in-the-next-report"))

      expect(config_keys_reported_in(sdk_server.next_telemetry_request)).to eq(["read-in-the-next-report"])
      expect(logger.messages_at(:warn)).to eq(
        [
          "[EventReporter] The telemetry endpoint responded with status 500. " \
          "The events in this report were discarded."
        ]
      )
    end
  end

  describe "when the SDK server answers 204" do
    it "logs at debug level that the report was sent, and no warning" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("day-of-the-week"))
      telemetry.start_reporting

      sdk_server.next_telemetry_request.answer(status: 204)
      Waiting.wait_up_to(2) { logger.messages_at(:debug).any? }

      expect(logger.messages_at(:debug)).to eq(["[EventReporter] Telemetry report successfully sent."])
      expect(logger.messages_at(:warn)).to eq([])
    end
  end

  describe "when the SDK server drops the connection without an answer" do
    it "discards that report, logs one warning with the cause and sends the next report" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-in-the-report-that-got-no-answer"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request.drop

      telemetry.record(read_of("read-in-the-next-report"))

      expect(config_keys_reported_in(sdk_server.next_telemetry_request)).to eq(["read-in-the-next-report"])
      warnings = logger.messages_at(:warn)
      expect(warnings.length).to eq(1)
      expect(warnings.first).to start_with("[EventReporter] Error attempting to send telemetry data: EOFError: ")
    end
  end

  describe "when the SDK server does not answer in time" do
    it "gives the report up after the time a report may take, logs one warning and sends the next report" do
      telemetry = telemetry_reporting(seconds_a_report_may_take: 0.3)
      telemetry.record(read_of("read-in-the-report-that-timed-out"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request

      telemetry.record(read_of("read-in-the-next-report"))
      seconds_before_the_next_report = seconds_taken { sdk_server.next_telemetry_request }

      expect(seconds_before_the_next_report).to be_between(0.25, 1)
      expect(logger.messages_at(:warn)).to eq(
        [
          "[EventReporter] Error attempting to send telemetry data: " \
          "the SDK server gave no complete answer within 0.3 seconds"
        ]
      )
    end
  end

  describe "when a report cannot be written" do
    let(:context_with_a_trait_that_cannot_be_written) do
      trait_that_cannot_be_written = Object.new
      def trait_that_cannot_be_written.to_s
        raise "no text for this trait"
      end

      ConfigDirector::Context.new(id: "user-1", traits: { "plan" => trait_that_cannot_be_written })
    end

    it "logs one warning, sends nothing of that report and sends the next report" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-in-the-report-that-cannot-be-written",
                               context: context_with_a_trait_that_cannot_be_written))
      telemetry.start_reporting
      Waiting.wait_up_to(2) { logger.messages_at(:warn).any? }

      telemetry.record(read_of("read-in-the-next-report"))

      expect(config_keys_reported_in(sdk_server.next_telemetry_request)).to eq(["read-in-the-next-report"])
      expect(logger.messages_at(:warn)).to eq(
        ['[TelemetryEventCollector] Error flushing telemetry events: RuntimeError: "no text for this trait"']
      )
    end

    it "logs one warning and sends nothing when it is closed" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("day-of-the-week", context: context_with_a_trait_that_cannot_be_written))

      telemetry.close

      expect(no_report_arrives_within?(0)).to be(true)
      expect(logger.messages_at(:warn)).to eq(
        ['[TelemetryEventCollector] Error flushing telemetry events: RuntimeError: "no text for this trait"']
      )
    end
  end

  describe "when nothing listens at the URL" do
    it "logs one warning with the cause when it is closed" do
      telemetry = telemetry_reporting_to(
        ScriptedSdkServer.url_nothing_listens_on,
        ConfigDirector::Internal::Telemetry::ReportTiming.of_a_client_reporting_every(30)
      )
      telemetry.record(read_of("day-of-the-week"))

      telemetry.close

      warnings = logger.messages_at(:warn)
      expect(warnings.length).to eq(1)
      expect(warnings.first).to start_with("[EventReporter] Error attempting to send telemetry data: Errno::")
    end
  end

  describe "when it is closed" do
    it "waits for a report that is being sent, then sends the last report" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-in-the-report-being-sent"))
      telemetry.start_reporting
      request_being_sent = sdk_server.next_telemetry_request
      telemetry.record(read_of("read-in-the-last-report"))

      closing = Thread.new { telemetry.close }
      no_last_report_while_one_is_being_sent = no_report_arrives_within?(0.3)
      request_being_sent.answer(status: 204)
      last_request = sdk_server.next_telemetry_request
      closed_before_the_last_report_was_answered = !closing.join(0.3).nil?
      last_request.answer(status: 204)

      expect(no_last_report_while_one_is_being_sent).to be(true)
      expect(config_keys_reported_in(last_request)).to eq(["read-in-the-last-report"])
      expect(closed_before_the_last_report_was_answered).to be(false)
      expect(closing.join(2)).not_to be_nil
    end

    it "returns within the time two reports may take when the SDK server answers neither" do
      telemetry = telemetry_reporting(seconds_a_report_may_take: 0.3)
      telemetry.record(read_of("read-in-the-report-being-sent"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request
      telemetry.record(read_of("read-in-the-last-report"))

      seconds_close_took = seconds_taken { telemetry.close }

      expect(seconds_close_took).to be_between(0.25, 1)
      expect(config_keys_reported_in(sdk_server.next_telemetry_request(within: 0))).to eq(["read-in-the-last-report"])
    end

    it "sends nothing for a read recorded afterwards when it is closed again" do
      telemetry = telemetry_reporting
      telemetry.close
      telemetry.record(read_of("read-after-close"))

      telemetry.close

      expect(no_report_arrives_within?(0.2)).to be(true)
    end

    it "sends no report on its schedule afterwards" do
      telemetry = telemetry_reporting
      telemetry.start_reporting

      telemetry.close
      telemetry.record(read_of("read-after-close"))

      expect(no_report_arrives_within?(0.3)).to be(true)
    end
  end

  describe "an invalid context kind" do
    it "is new the first time and known the second time" do
      telemetry = telemetry_reporting

      expect(telemetry.count_invalid_context("Device")).to eq(:new_kind_sample)
      expect(telemetry.count_invalid_context("Device")).to eq(:known_kind_sample)
    end

    it "is new again after a report" do
      telemetry = telemetry_reporting
      telemetry.count_invalid_context("Device")
      telemetry.start_reporting
      sdk_server.next_telemetry_request.answer(status: 204)

      expect(telemetry.count_invalid_context("Device")).to eq(:new_kind_sample)
    end

    it "is the first beyond the sample limit when it is the 21st different kind, and beyond it afterwards" do
      telemetry = telemetry_reporting
      20.times { |number| telemetry.count_invalid_context("Kind #{number}") }

      expect(telemetry.count_invalid_context("Kind 20")).to eq(:first_beyond_sample_limit)
      expect(telemetry.count_invalid_context("Kind 21")).to eq(:beyond_sample_limit)
    end

    it "stays known after a refusal that stopped the reports" do
      telemetry = telemetry_reporting
      telemetry.record(read_of("read-before-the-refusal"))
      telemetry.start_reporting
      sdk_server.next_telemetry_request.answer(status: 401)
      Waiting.wait_up_to(2) { logger.messages_at(:warn).any? }
      telemetry.count_invalid_context("Device")

      expect(telemetry.count_invalid_context("Device")).to eq(:known_kind_sample)
      expect(no_report_arrives_within?(0.3)).to be(true)
    end
  end
end
