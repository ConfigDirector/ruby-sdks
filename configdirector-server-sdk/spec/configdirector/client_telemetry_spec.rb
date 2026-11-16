# frozen_string_literal: true

require "rbconfig"
require_relative "../support/elapsed_seconds"
require_relative "../support/sdk_server_serving_the_sample_configs"

RSpec.describe "A client's telemetry" do
  include ElapsedSeconds

  include_context "with an SDK server that serves the sample configs"

  let(:client) { client_of_the_sample_configs(logger: logger) }

  def report_sent_by_closing(client)
    client.close

    sdk_server.next_telemetry_request(within: 0).json
  end

  def evaluations_in(report)
    report.fetch("aggregatedEvents").fetch("evaluatedConfig")
  end

  def events_in(report)
    evaluations_in(report).map { |evaluation| evaluation.fetch("event") }
  end

  def captured_contexts_in(report)
    report.fetch("discreteEvents").fetch("capturedContexts")
  end

  def invalid_contexts_in(report)
    report.fetch("aggregatedEvents").fetch("invalidContext")
  end

  describe "of an evaluation" do
    before { client.init }

    it "reports two identical reads as one evaluation with a count of 2" do
      2.times { client.get_value("day-of-the-week-config", "Sunday") }

      evaluations = evaluations_in(report_sent_by_closing(client))

      expect(evaluations.length).to eq(1)
      expect(evaluations.first.fetch("count")).to eq(2)
      expect(evaluations.first.fetch("event")).to eq(
        "key" => "day-of-the-week-config", "type" => "string", "defaultValue" => { "value" => "Sunday" },
        "requestedType" => "String", "evaluatedValue" => { "value" => "Monday" },
        "evaluatedValueId" => "value-monday", "usedDefault" => false, "evaluationReason" => "found-match"
      )
    end

    it "reports two reads with different in-code default values as two evaluations" do
      client.get_value("day-of-the-week-config", "Sunday")
      client.get_value("day-of-the-week-config", "Saturday")

      evaluations = evaluations_in(report_sent_by_closing(client))

      expect(evaluations.map { |evaluation| evaluation.fetch("count") }).to eq([1, 1])
      expect(evaluations.map { |evaluation| evaluation.fetch("event").fetch("defaultValue") }).to eq(
        [{ "value" => "Sunday" }, { "value" => "Saturday" }]
      )
    end

    it "reports when the evaluations were collected, in UTC with milliseconds" do
      collected_from = Time.now
      client.get_value("day-of-the-week-config", "Sunday")

      evaluation = evaluations_in(report_sent_by_closing(client)).first

      start_time = evaluation.fetch("startTime")
      end_time = evaluation.fetch("endTime")
      expect([start_time, end_time]).to all(match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/))
      expect(Time.iso8601(start_time)).to be_between(collected_from - 1, Time.now)
      expect(Time.iso8601(end_time)).to be_between(Time.iso8601(start_time), Time.now)
    end

    it "reports a read of a config that does not exist as the in-code default value with its reason" do
      client.get_value("no-such-config", "Sunday")

      expect(events_in(report_sent_by_closing(client))).to eq(
        [{
          "key" => "no-such-config", "defaultValue" => { "value" => "Sunday" }, "requestedType" => "String",
          "evaluatedValue" => { "value" => "Sunday" }, "usedDefault" => true,
          "evaluationReason" => "config-state-missing"
        }]
      )
    end

    it "reports a read the config's type cannot answer with the config's type and the reason" do
      client.get_value("integer-config", "Sunday")

      expect(events_in(report_sent_by_closing(client))).to eq(
        [{
          "key" => "integer-config", "type" => "integer", "defaultValue" => { "value" => "Sunday" },
          "requestedType" => "String", "evaluatedValue" => { "value" => "Sunday" }, "usedDefault" => true,
          "evaluationReason" => "type-mismatch"
        }]
      )
    end

    it "reports a JSON read by value IDs of 22 characters, with the requested type Hash" do
      client.get_value("json-value-config", { "greeting" => "hi" })

      event = events_in(report_sent_by_closing(client)).first

      expect(event).to include(
        "type" => "json", "requestedType" => "Hash", "defaultValue" => { "valueId" => "2nSU077zdp6QUP84OcTEOx" },
        "evaluatedValue" => { "valueId" => "value-json-greeting" }, "evaluatedValueId" => "value-json-greeting"
      )
      expect(event.fetch("defaultValue").fetch("valueId").length).to eq(22)
    end

    it "reports a JSON array read with the requested type Array" do
      client.get_value("json-list-config", [])

      expect(events_in(report_sent_by_closing(client)).first).to include(
        "requestedType" => "Array", "evaluatedValue" => { "valueId" => "value-json-sizes" }
      )
    end

    it "reports a Hash that was returned as the in-code default value by the value ID of its JSON text" do
      client.get_value("malformed-json-config", { "greeting" => "hi" })

      expect(events_in(report_sent_by_closing(client)).first).to include(
        "evaluatedValue" => { "valueId" => "2nSU077zdp6QUP84OcTEOx" }, "usedDefault" => true,
        "evaluationReason" => "invalid-json"
      )
    end

    it "reports the text that a JSON config was read as by the value ID of its JSON text" do
      client.get_value("json-value-config", "abc")

      expect(events_in(report_sent_by_closing(client)).first).to include(
        "type" => "json", "requestedType" => "String", "defaultValue" => { "valueId" => "3JEr89u1fHkS1ecgN9MQmS" },
        "evaluatedValue" => { "valueId" => "value-json-greeting" }
      )
    end

    it "reports two reads whose in-code default values are the same JSON text as one evaluation" do
      client.get_value("no-such-config", { "n" => 5 })
      client.get_value("no-such-config", { n: 5 })

      evaluations = evaluations_in(report_sent_by_closing(client))

      expect(evaluations.map { |evaluation| evaluation.fetch("count") }).to eq([2])
    end

    it "pads a value ID with zeros to 22 characters" do
      client.get_value("no-such-config", { "n" => 5 })

      expect(events_in(report_sent_by_closing(client)).first.fetch("defaultValue")).to eq(
        "valueId" => "0XcE3kA5nRwHO59ozjgAoQ"
      )
    end

    it "reports a read with true under the requested type Boolean" do
      client.get_value("permanent-kill-switch", true)

      expect(events_in(report_sent_by_closing(client)).first).to include(
        "requestedType" => "Boolean", "defaultValue" => { "value" => "true" }, "evaluatedValue" => { "value" => "true" }
      )
    end

    it "reports a read with false under the requested type Boolean" do
      client.get_value("permanent-kill-switch", false)

      expect(events_in(report_sent_by_closing(client)).first).to include(
        "requestedType" => "Boolean", "defaultValue" => { "value" => "false" },
        "evaluatedValue" => { "value" => "true" }
      )
    end

    it "reports an Integer read with the requested type Integer and the number as text" do
      client.get_value("integer-config", 0)

      expect(events_in(report_sent_by_closing(client)).first).to include(
        "requestedType" => "Integer", "defaultValue" => { "value" => "0" }, "evaluatedValue" => { "value" => "42" }
      )
    end

    it "reports a Float read with the requested type Float and the numbers as JavaScript writes them" do
      client.get_value("float-config", 1.0)

      expect(events_in(report_sent_by_closing(client)).first).to include(
        "requestedType" => "Float", "defaultValue" => { "value" => "1" }, "evaluatedValue" => { "value" => "26" }
      )
    end

    it "reports an in-code default value of 501 characters by its value ID" do
      client.get_value("no-such-config", "x" * 501)

      expect(events_in(report_sent_by_closing(client)).first).to include(
        "defaultValue" => { "valueId" => "1msimcF2S2uAnyUbYhc3eb" },
        "evaluatedValue" => { "valueId" => "1msimcF2S2uAnyUbYhc3eb" }
      )
    end

    it "reports an in-code default value of 500 characters as its text" do
      client.get_value("no-such-config", "x" * 500)

      expect(events_in(report_sent_by_closing(client)).first.fetch("defaultValue")).to eq("value" => "x" * 500)
    end

    it "reports the rule, the share and the variation of a percentage rollout that served the value" do
      client.get_value("temporary-feature-flag", false, ConfigDirector::Context.new(id: "user-1"))

      expect(events_in(report_sent_by_closing(client)).first).to include(
        "ruleId" => "rule-flag-rollout", "shareId" => "share-flag-on", "variationId" => "variation-flag-on",
        "evaluatedValue" => { "value" => "true" }, "evaluatedValueId" => "value-flag-on"
      )
    end

    it "reports no rule, share, variation or value ID for a read that returned the in-code default value" do
      client.get_value("temporary-feature-flag", "text", ConfigDirector::Context.new(id: "user-1"))

      event = events_in(report_sent_by_closing(client)).first

      expect(event).to include("usedDefault" => true, "evaluationReason" => "type-mismatch")
      expect(event.keys).not_to include("ruleId", "shareId", "variationId", "evaluatedValueId")
    end

    it "reports the variation and no rule when the default targeting rule served the value" do
      client.get_value("temporary-feature-flag", true)

      event = events_in(report_sent_by_closing(client)).first

      expect(event).to include(
        "variationId" => "variation-flag-off", "evaluationReason" => "rollout-skipped-no-identifier"
      )
      expect(event.keys).not_to include("ruleId", "shareId")
    end

    it "reports no rule for a value that a conditional rule served" do
      client_of_another_application = client_of_the_sample_configs(
        metadata: ConfigDirector::Metadata.new(app_name: "beta-app")
      )
      client_of_another_application.init
      client_of_another_application.get_value("integer-config", 0)

      event = events_in(report_sent_by_closing(client_of_another_application)).first

      expect(event).to include("evaluatedValue" => { "value" => "7" }, "evaluatedValueId" => "value-integer-7")
      expect(event.keys).not_to include("ruleId", "shareId", "variationId")
    end

    it "reports evaluate as it reports get_value" do
      client.evaluate("day-of-the-week-config", "Sunday")

      expect(events_in(report_sent_by_closing(client)).first).to include(
        "key" => "day-of-the-week-config", "evaluatedValue" => { "value" => "Monday" }
      )
    end

    it "reports nothing for get_all_configs" do
      client.get_all_configs

      client.close

      expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 0)).to be(false)
    end

    it "reports a config key that is not text as its text" do
      client.get_value(5, "Sunday")

      expect(events_in(report_sent_by_closing(client)).first.fetch("key")).to eq("5")
    end
  end

  describe "of a watch" do
    it "reports each delivery to a watch as one evaluation" do
      client.watch("day-of-the-week-config", "Sunday") { |_day| nil }
      client.init

      expect(evaluations_in(report_sent_by_closing(client))).to contain_exactly(
        include("count" => 1, "event" => include("key" => "day-of-the-week-config", "usedDefault" => false))
      )
    end
  end

  describe "of a read before init" do
    it "keeps the read and reports it once the client is closed" do
      client.get_value("day-of-the-week-config", "Sunday")

      expect(events_in(report_sent_by_closing(client))).to eq(
        [{
          "key" => "day-of-the-week-config", "defaultValue" => { "value" => "Sunday" },
          "requestedType" => "String", "evaluatedValue" => { "value" => "Sunday" }, "usedDefault" => true,
          "evaluationReason" => "client-not-ready"
        }]
      )
    end

    it "reports it with the reads that follow init" do
      client.get_value("day-of-the-week-config", "Sunday")
      client.init
      client.get_value("day-of-the-week-config", "Sunday")

      expect(events_in(report_sent_by_closing(client)).map { |event| event.fetch("evaluationReason") }).to eq(
        %w[client-not-ready found-match]
      )
    end
  end

  describe "of a context" do
    before { client.init }

    it "captures an identified context once, with its name and traits, and names it on its evaluations" do
      context = ConfigDirector::Context.new(id: "user-1", name: "Ada", traits: { plan: "pro", seats: 3 })
      2.times { client.get_value("day-of-the-week-config", "Sunday", context) }
      client.get_value("integer-config", 0, context)

      report = report_sent_by_closing(client)

      expect(captured_contexts_in(report)).to eq(
        [{ "id" => "user-1", "kind" => "user", "name" => "Ada", "traits" => { "plan" => "pro", "seats" => 3 } }]
      )
      expect(events_in(report)).to all(include("contextId" => "user-1", "contextKind" => "user"))
    end

    it "captures a context of another kind under its kind" do
      client.get_value("day-of-the-week-config", "Sunday", ConfigDirector::Context.new(id: "device-1", kind: "device"))

      report = report_sent_by_closing(client)

      expect(captured_contexts_in(report)).to eq([{ "id" => "device-1", "kind" => "device" }])
      expect(events_in(report).first).to include("contextId" => "device-1", "contextKind" => "device")
    end

    it "captures two contexts with the same identifier and different kinds as two contexts" do
      client.get_value("day-of-the-week-config", "Sunday", ConfigDirector::Context.new(id: "1"))
      client.get_value("day-of-the-week-config", "Sunday", ConfigDirector::Context.new(id: "1", kind: "device"))

      expect(captured_contexts_in(report_sent_by_closing(client))).to eq(
        [{ "id" => "1", "kind" => "user" }, { "id" => "1", "kind" => "device" }]
      )
    end

    it "captures the context as it was last given" do
      client.get_value("day-of-the-week-config", "Sunday", ConfigDirector::Context.new(id: "user-1", name: "Ada"))
      client.get_value("day-of-the-week-config", "Sunday", ConfigDirector::Context.new(id: "user-1", name: "Grace"))

      expect(captured_contexts_in(report_sent_by_closing(client))).to eq(
        [{ "id" => "user-1", "kind" => "user", "name" => "Grace" }]
      )
    end

    it "neither captures an anonymous context nor names it on its evaluation" do
      context = ConfigDirector::Context.new(id: "user-1", name: "Ada", anonymous: true)
      client.get_value("day-of-the-week-config", "Sunday", context)

      report = report_sent_by_closing(client)

      expect(captured_contexts_in(report)).to eq([])
      expect(events_in(report).first.keys).not_to include("contextId", "contextKind")
    end

    it "neither captures a context without an identifier nor names it on its evaluation" do
      client.get_value("day-of-the-week-config", "Sunday", ConfigDirector::Context.new(traits: { plan: "pro" }))

      report = report_sent_by_closing(client)

      expect(captured_contexts_in(report)).to eq([])
      expect(events_in(report).first.keys).not_to include("contextId", "contextKind")
    end

    it "neither captures a context with an empty identifier nor names it on its evaluation" do
      client.get_value("day-of-the-week-config", "Sunday", ConfigDirector::Context.new(id: ""))

      report = report_sent_by_closing(client)

      expect(captured_contexts_in(report)).to eq([])
      expect(events_in(report).first.keys).not_to include("contextId", "contextKind")
    end

    it "writes a trait that is not a finite number as null" do
      context = ConfigDirector::Context.new(id: "user-1", traits: { score: Float::NAN, ratio: 0.5 })
      client.get_value("day-of-the-week-config", "Sunday", context)

      expect(captured_contexts_in(report_sent_by_closing(client)).first.fetch("traits")).to eq(
        "score" => nil, "ratio" => 0.5
      )
    end
  end

  describe "of a context with an invalid kind" do
    before { client.init }

    it "counts the context under a sample of its kind, and reports nothing else of it" do
      context = ConfigDirector::Context.new(id: "device-1", kind: "Device", name: "Ada", traits: { plan: "pro" })
      2.times { client.get_value("day-of-the-week-config", "Sunday", context) }

      report = report_sent_by_closing(client)

      expect(invalid_contexts_in(report)).to contain_exactly(
        include("count" => 2, "event" => { "reason" => "invalid-context-kind", "kindSample" => "Device" })
      )
      expect(captured_contexts_in(report)).to eq([])
      expect(events_in(report).first.keys).not_to include("contextId", "contextKind")
      expect(JSON.generate(report)).not_to include("device-1", "Ada", "pro")
    end

    it "counts the 21st and later different kinds together, without a sample" do
      23.times do |number|
        client.get_value("day-of-the-week-config", "Sunday", ConfigDirector::Context.new(kind: "Kind #{number}"))
      end

      invalid_contexts = invalid_contexts_in(report_sent_by_closing(client))

      expect(invalid_contexts.length).to eq(21)
      expect(invalid_contexts.first.fetch("event")).to eq("reason" => "invalid-context-kind", "kindSample" => "Kind 0")
      expect(invalid_contexts[19].fetch("event")).to eq("reason" => "invalid-context-kind", "kindSample" => "Kind 19")
      expect(invalid_contexts.last).to include("count" => 3, "event" => { "reason" => "invalid-context-kind" })
    end

    it "counts a context given to get_all_configs" do
      client.get_all_configs(context: ConfigDirector::Context.new(kind: "Device"))

      report = report_sent_by_closing(client)

      expect(invalid_contexts_in(report)).to contain_exactly(
        include("count" => 1, "event" => { "reason" => "invalid-context-kind", "kindSample" => "Device" })
      )
      expect(evaluations_in(report)).to eq([])
    end
  end

  describe "over the event queue limit" do
    let(:client) do
      client_of_the_sample_configs(
        logger: logger, telemetry: ConfigDirector::TelemetryOptions.new(event_queue_limit: 101)
      )
    end

    before { client.init }

    it "keeps the newest evaluations of 70% of the limit, rounded up, and reports how many it dropped" do
      73.times { |number| client.get_value("config-#{number}", "Sunday") }

      report = report_sent_by_closing(client)

      keys_reported = events_in(report).map { |event| event.fetch("key") }
      expect(report.fetch("droppedEvents").fetch("evaluatedConfig")).to eq(2)
      expect(keys_reported.length).to eq(71)
      expect(keys_reported.first).to eq("config-2")
      expect(keys_reported.last).to eq("config-72")
    end

    it "keeps the newest contexts of 30% of the limit, rounded down, and reports how many it dropped" do
      32.times do |number|
        client.get_value("day-of-the-week-config", "Sunday", ConfigDirector::Context.new(id: "user-#{number}"))
      end

      report = report_sent_by_closing(client)

      identifiers_captured = captured_contexts_in(report).map { |context| context.fetch("id") }
      expect(report.fetch("droppedEvents")).to eq("evaluatedConfig" => 0, "capturedContexts" => 2)
      expect(identifiers_captured.length).to eq(30)
      expect(identifiers_captured.first).to eq("user-2")
      expect(identifiers_captured.last).to eq("user-31")
    end
  end

  describe "report" do
    it "carries the server SDK key, the SDK's name and version, and the application's" do
      client = client_of_the_sample_configs(
        logger: logger, metadata: ConfigDirector::Metadata.new(app_name: "storefront", app_version: "2.4.0")
      )
      client.get_value("day-of-the-week-config", "Sunday")

      report = report_sent_by_closing(client)

      expect(report.fetch("serverSdkKey")).to eq("server-sdk-key")
      expect(report.fetch("metaContext")).to eq(
        "sdkName" => "ruby-server-sdk", "sdkVersion" => ConfigDirector::VERSION, "appName" => "storefront",
        "appVersion" => "2.4.0"
      )
    end

    it "is sent as JSON, under the SDK's name and version as the user agent" do
      client.get_value("day-of-the-week-config", "Sunday")
      client.close

      headers = sdk_server.next_telemetry_request(within: 0).headers

      expect(headers.fetch("content-type")).to eq("application/json")
      expect(headers.fetch("user-agent")).to eq("ruby-server-sdk/#{ConfigDirector::VERSION}")
    end

    it "is not sent when nothing was collected" do
      client.init

      client.close

      expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 0)).to be(false)
    end

    it "is not sent again by a second close" do
      client.get_value("day-of-the-week-config", "Sunday")
      client.close
      sdk_server.next_telemetry_request(within: 0)

      client.close

      expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 0)).to be(false)
    end

    it "logs at debug level that it was sent" do
      client.get_value("day-of-the-week-config", "Sunday")

      client.close

      expect(logger.messages_at(:debug)).to include("[EventReporter] Telemetry report successfully sent.")
    end
  end

  describe "schedule" do
    it "sends the first report 5 seconds after init and the next one a flush interval later" do
      client = client_of_the_sample_configs(
        logger: logger, telemetry: ConfigDirector::TelemetryOptions.new(flush_interval: 1)
      )
      client.init
      client.get_value("day-of-the-week-config", "read after init")

      first_report = nil
      seconds_before_the_first_report = seconds_taken do
        first_report = sdk_server.next_telemetry_request(within: 8).json
      end
      client.get_value("day-of-the-week-config", "read after the first report")
      second_report = nil
      seconds_before_the_second_report = seconds_taken do
        second_report = sdk_server.next_telemetry_request(within: 4).json
      end

      expect(seconds_before_the_first_report).to be_between(4.5, 6.5)
      expect(events_in(first_report).map { |event| event.fetch("defaultValue") }).to eq(
        [{ "value" => "read after init" }]
      )
      expect(seconds_before_the_second_report).to be_between(0.5, 2)
      expect(events_in(second_report).map { |event| event.fetch("defaultValue") }).to eq(
        [{ "value" => "read after the first report" }]
      )
    end

    it "starts no thread for a client that was created and read, and never initialized" do
      threads_before_the_client = Thread.list

      client.get_value("day-of-the-week-config", "Sunday")

      expect(Thread.list).to eq(threads_before_the_client)
    end

    it "starts one telemetry thread at the first init, and none at a later one" do
      client.init
      client.init

      expect(sdk_threads_alive.map(&:name).count("configdirector-telemetry")).to eq(1)
    end

    it "ends its telemetry thread when the client is closed" do
      client.init

      client.close
      wait_until_no_sdk_thread_is_alive

      expect(sdk_threads_alive.map(&:name)).not_to include("configdirector-telemetry")
    end
  end

  describe "when the SDK server does not answer a report" do
    it "gives the report up after 5 seconds and logs a warning" do
      sdk_server.hold_telemetry_reports
      client.get_value("day-of-the-week-config", "Sunday")

      seconds_close_took = seconds_taken { client.close }

      expect(seconds_close_took).to be_between(4.5, 6.5)
      expect(logger.messages_at(:warn)).to eq(
        [
          "[EventReporter] Error attempting to send telemetry data: " \
          "the SDK server gave no complete answer within 5 seconds"
        ]
      )
    end
  end

  describe "of a process that exits without closing its client" do
    it "sends nothing when the process exits" do
      exited_successfully = system(
        RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__),
        File.expand_path("../support/process_that_exits_without_closing_its_client.rb", __dir__), sdk_server.url
      )

      expect(exited_successfully).to be(true)
      expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 0.2)).to be(false)
    end
  end

  describe "at close" do
    it "sends what was collected before close returns" do
      client.init
      client.get_value("day-of-the-week-config", "Sunday")

      client.close

      expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 0)).to be(true)
    end

    it "reports no read made after the client was closed" do
      client.init
      client.close

      client.get_value("day-of-the-week-config", "Sunday")
      client.close

      expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 0)).to be(false)
    end
  end
end

RSpec.describe "A client's telemetry of values that ConfigDirector sent with a value ID" do
  include_context "with a client of the scripted SDK server"

  def event_reported_by_closing(client)
    client.close

    sdk_server.next_telemetry_request(within: 0).json.fetch("aggregatedEvents").fetch("evaluatedConfig").first
              .fetch("event")
  end

  it "reports a served value longer than 500 characters by that value ID" do
    client, = streaming_client_initialized_with(full_payload_text(configs: [wire_config("terms", "x" * 501)]))
    client.get_value("terms", "none")

    expect(event_reported_by_closing(client)).to include(
      "evaluatedValue" => { "valueId" => "value-id-of-terms" }, "evaluatedValueId" => "value-id-of-terms"
    )
  end

  it "reports the JSON text of a text config that was read as a Hash by that value ID" do
    client, = streaming_client_initialized_with(
      full_payload_text(configs: [wire_config("banner", '{"greeting":"hello"}', type: "string")])
    )
    client.get_value("banner", {})

    expect(event_reported_by_closing(client)).to include(
      "type" => "string", "usedDefault" => false, "evaluatedValue" => { "valueId" => "value-id-of-banner" }
    )
  end
end

RSpec.describe "A polling client's telemetry" do
  include_context "with a client of the scripted SDK server"

  it "starts one telemetry thread at init and sends what was read when the client is closed" do
    client = polling_client_initialized_with(full_payload_text(configs: [wire_config("day-of-the-week", "Monday")]))
    client.get_value("day-of-the-week", "Sunday")
    telemetry_threads_after_init = sdk_threads_alive.map(&:name).count("configdirector-telemetry")

    client.close
    evaluations = sdk_server.next_telemetry_request(within: 0).json.fetch("aggregatedEvents").fetch("evaluatedConfig")

    expect(telemetry_threads_after_init).to eq(1)
    expect(evaluations.map { |evaluation| evaluation.fetch("event").fetch("evaluatedValue") }).to eq(
      [{ "value" => "Monday" }]
    )
  end
end
