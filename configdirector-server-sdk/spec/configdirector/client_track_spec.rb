# frozen_string_literal: true

require_relative "../support/elapsed_seconds"
require_relative "../support/sdk_server_serving_the_sample_configs"

RSpec.describe "A client's tracked events" do
  include ElapsedSeconds

  include_context "with an SDK server that serves the sample configs"

  let(:client) { client_of_the_sample_configs(logger: logger) }

  def tracked_events_reported_by_closing(client)
    client.close

    sdk_server.next_telemetry_request(within: 0).json.fetch("discreteEvents").fetch("trackedEvents")
  end

  it "reports a tracked event with its context, value and details in the next report, with the time of the call" do
    client.init
    tracked_from = Time.now
    client.track(
      "checkout-completed", ConfigDirector::Context.new(id: "user-123"), value: 49.9, details: { "plan" => "pro" }
    )

    tracked_events = tracked_events_reported_by_closing(client)

    expect(tracked_events.length).to eq(1)
    expect(tracked_events.first.except("happenedAt")).to eq(
      "name" => "checkout-completed", "contextKind" => "user", "contextIdentifier" => "user-123", "value" => 49.9,
      "details" => { "plan" => "pro" }
    )
    happened_at = tracked_events.first.fetch("happenedAt")
    expect(happened_at).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)
    expect(Time.iso8601(happened_at)).to be_between(tracked_from - 1, Time.now)
  end

  describe "per report" do
    it "reports the first 1,000 events and drops the 1,001st and later ones, logging one warning" do
      1_002.times { |number| client.track("event-#{number}") }

      tracked_events = tracked_events_reported_by_closing(client)

      expect(tracked_events.length).to eq(1_000)
      expect(tracked_events.last.fetch("name")).to eq("event-999")
      expect(logger.messages_at(:warn)).to eq(
        [
          "[ConfigDirectorClient] A tracked event was not reported because 1000 tracked events are already waiting " \
          "for the next telemetry batch. Further tracked events like it are not logged until the next telemetry " \
          "batch is sent."
        ]
      )
    end
  end

  describe "name" do
    it "drops an event whose name has 151 characters, logging one warning for two such events" do
      client.track("é" * 151)
      client.track("x" * 151)
      client.track("checkout-completed")

      tracked_events = tracked_events_reported_by_closing(client)

      expect(tracked_events.map { |tracked_event| tracked_event.fetch("name") }).to eq(["checkout-completed"])
      expect(logger.messages_at(:warn)).to eq(
        [
          "[ConfigDirectorClient] A tracked event was not reported because its name does not have 1 to 150 " \
          "characters. Further tracked events like it are not logged until the next telemetry batch is sent."
        ]
      )
    end

    it "reports an event whose name has 150 characters" do
      client.track("é" * 150)

      expect(tracked_events_reported_by_closing(client).first.fetch("name")).to eq("é" * 150)
    end

    it "counts the characters of a name given as the bytes of UTF-8 text" do
      client.track(("é" * 150).b)

      expect(tracked_events_reported_by_closing(client).first.fetch("name")).to eq("é" * 150)
    end

    it "drops an event with an empty name" do
      client.track("")
      client.track("checkout-completed")

      expect(tracked_events_reported_by_closing(client).map { |tracked_event| tracked_event.fetch("name") }).to eq(
        ["checkout-completed"]
      )
    end

    it "reads a Symbol name as its name" do
      client.track(:checkout_completed)

      expect(tracked_events_reported_by_closing(client).first.fetch("name")).to eq("checkout_completed")
    end

    it "drops an event whose name is neither a String nor a Symbol, logging the name warning" do
      client.track(42)
      client.track("checkout-completed")

      expect(tracked_events_reported_by_closing(client).map { |tracked_event| tracked_event.fetch("name") }).to eq(
        ["checkout-completed"]
      )
      expect(logger.messages_at(:warn)).to eq(
        [
          "[ConfigDirectorClient] A tracked event was not reported because its name does not have 1 to 150 " \
          "characters. Further tracked events like it are not logged until the next telemetry batch is sent."
        ]
      )
    end
  end

  describe "context" do
    it "reports the kind of a context of another kind" do
      client.track("device-paired", ConfigDirector::Context.new(id: "device-1", kind: "device"))

      expect(tracked_events_reported_by_closing(client).first).to include(
        "contextKind" => "device", "contextIdentifier" => "device-1"
      )
    end

    it "reports an event without a context with neither a kind nor an identifier" do
      client.track("checkout-completed")

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("contextKind", "contextIdentifier")
    end

    it "reports an event of an anonymous context with neither its kind nor its identifier" do
      client.track("checkout-completed", ConfigDirector::Context.new(id: "user-123", anonymous: true))

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("contextKind", "contextIdentifier")
    end

    it "reports an event of a context without an identifier with neither a kind nor an identifier" do
      client.track("checkout-completed", ConfigDirector::Context.new(kind: "device", traits: { "model" => "x1" }))

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("contextKind", "contextIdentifier")
    end

    it "does not capture the context of a tracked event" do
      client.track("checkout-completed", ConfigDirector::Context.new(id: "user-123", name: "Ada"))

      client.close

      expect(sdk_server.next_telemetry_request(within: 0).json.fetch("discreteEvents").fetch("capturedContexts")).to eq(
        []
      )
    end

    it "reports an event of a context with an invalid kind without the context, logging and counting the kind" do
      client.track("checkout-completed", ConfigDirector::Context.new(id: "device-1", kind: "Device"))

      client.close
      report = sdk_server.next_telemetry_request(within: 0).json

      expect(report.fetch("discreteEvents").fetch("trackedEvents").first.keys).not_to include(
        "contextKind", "contextIdentifier"
      )
      expect(report.fetch("aggregatedEvents").fetch("invalidContext")).to contain_exactly(
        include("count" => 1, "event" => { "reason" => "invalid-context-kind", "kindSample" => "Device" })
      )
      expect(logger.messages_at(:error)).to eq(
        [
          "[ConfigDirectorClient] Ignored a context with the invalid kind 'Device' and evaluated as if no context " \
          "was supplied. A context kind has 1 to 64 characters, using only lowercase letters, digits, '-' and '_'."
        ]
      )
    end

    it "drops an event whose context is not a Context, logging a warning and raising nothing" do
      client.track("checkout-completed", "user-123")
      client.track("items-added")

      expect(tracked_events_reported_by_closing(client).map { |tracked_event| tracked_event.fetch("name") }).to eq(
        ["items-added"]
      )
      expect(logger.messages_at(:warn)).to eq(
        [
          "[ConfigDirectorClient] A tracked event was not reported because it could not be read: " \
          "ConfigDirector::ConfigDirectorValidationError: " \
          "\"Invalid context of class String. A context must be a ConfigDirector::Context.\""
        ]
      )
    end
  end

  it "returns nil" do
    expect(client.track("checkout-completed")).to be_nil
  end

  describe "of a closed client" do
    it "reports nothing and logs nothing" do
      client.init
      client.close

      client.track("checkout-completed", ConfigDirector::Context.new(kind: "Device"), value: Float::NAN)
      client.close

      expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 0)).to be(false)
      expect(logger.messages_at(:warn)).to eq([])
      expect(logger.messages_at(:error)).to eq([])
    end
  end

  describe "of an offline client" do
    it "sends nothing, starts no thread and logs nothing" do
      sdk_server_url = sdk_server.url
      threads_before_the_client = Thread.list
      client = ConfigDirector.create_client(
        connection: ConfigDirector::ConnectionOptions.new(mode: "offline", url: sdk_server_url), logger: logger
      )
      client.init

      client.track("checkout-completed", ConfigDirector::Context.new(kind: "Device"), value: Float::NAN)
      client.track("checkout-completed", "user-123")
      client.close

      expect(Thread.list).to eq(threads_before_the_client)
      expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 0.2)).to be(false)
      expect(logger.messages_at(:warn)).to eq([])
      expect(logger.messages_at(:error)).to eq([])
    end
  end

  describe "value" do
    it "leaves out a value of infinity, logging one warning for two such events, and still reports the events" do
      client.track("checkout-completed", value: Float::INFINITY)
      client.track("checkout-completed", value: -Float::INFINITY)

      tracked_events = tracked_events_reported_by_closing(client)

      expect(tracked_events.map { |tracked_event| tracked_event.except("happenedAt") }).to eq(
        [{ "name" => "checkout-completed" }, { "name" => "checkout-completed" }]
      )
      expect(logger.messages_at(:warn)).to eq(
        [
          "[ConfigDirectorClient] A tracked event was reported without its value because the value is not a " \
          "finite number. Further tracked events like it are not logged until the next telemetry batch is sent."
        ]
      )
    end

    it "leaves out a value that is not a number" do
      client.track("checkout-completed", value: "49.9")

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("value")
    end

    it "leaves out true as a value" do
      client.track("checkout-completed", value: true)

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("value")
    end

    it "leaves out a Rational value" do
      client.track("checkout-completed", value: Rational(1, 3))

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("value")
    end

    it "reports an Integer value" do
      client.track("items-added", value: 3)

      expect(tracked_events_reported_by_closing(client).first.fetch("value")).to eq(3)
    end

    it "leaves out an Integer larger than the largest Float" do
      client.track("items-added", value: 10**309)

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("value")
    end
  end

  describe "details" do
    def details_reported_by_closing(client)
      tracked_events_reported_by_closing(client).first.fetch("details")
    end

    def arrays_nested(levels, around:)
      levels.times.reduce(around) { |inner_array, _level| [inner_array] }
    end

    it "leaves out details of 21 top-level keys, logging one warning for two such events, and reports the events" do
      too_many_keys = 21.times.to_h { |number| ["key-#{number}", number] }
      client.track("checkout-completed", details: too_many_keys)
      client.track("checkout-completed", details: too_many_keys)

      tracked_events = tracked_events_reported_by_closing(client)

      expect(tracked_events.map { |tracked_event| tracked_event.except("happenedAt") }).to eq(
        [{ "name" => "checkout-completed" }, { "name" => "checkout-completed" }]
      )
      expect(logger.messages_at(:warn)).to eq(
        [
          "[ConfigDirectorClient] A tracked event was reported without its details because they are not an object, " \
          "have more than 20 top-level keys, are larger than 1024 bytes as JSON, or cannot be written as JSON. " \
          "Further tracked events like it are not logged until the next telemetry batch is sent."
        ]
      )
    end

    it "reports details of 20 top-level keys" do
      client.track("checkout-completed", details: 20.times.to_h { |number| ["key-#{number}", number] })

      expect(details_reported_by_closing(client).length).to eq(20)
    end

    it "leaves out details of 1,025 bytes as JSON" do
      client.track("checkout-completed", details: { "note" => "x" * 1_014 })

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("details")
    end

    it "reports details of 1,024 bytes as JSON" do
      client.track("checkout-completed", details: { "note" => "x" * 1_013 })

      expect(details_reported_by_closing(client)).to eq("note" => "x" * 1_013)
    end

    it "counts the bytes of the details as UTF-8 JSON, with numbers as JavaScript writes them" do
      client.track("checkout-completed", details: { "note" => "x#{"é" * 494}", "ratio" => 1.0e+21, "count" => 4.0 })

      expect(details_reported_by_closing(client)).to eq("note" => "x#{"é" * 494}", "ratio" => 1.0e+21, "count" => 4)
    end

    it "leaves out details over 1,024 bytes once their text is UTF-8" do
      client.track("checkout-completed", details: { "note" => "é" * 507 })

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("details")
    end

    it "reads Symbol keys as their names at any depth" do
      client.track("checkout-completed", details: { plan: "pro", cart: { items: [{ sku: "a-1" }] } })

      expect(details_reported_by_closing(client)).to eq(
        "plan" => "pro", "cart" => { "items" => [{ "sku" => "a-1" }] }
      )
    end

    it "reads a Symbol value as its name" do
      client.track("checkout-completed", details: { "plan" => :pro, "tiers" => [:gold] })

      expect(details_reported_by_closing(client)).to eq("plan" => "pro", "tiers" => ["gold"])
    end

    it "sends nil as null" do
      client.track("checkout-completed", details: { "coupon" => nil })

      expect(details_reported_by_closing(client)).to eq("coupon" => nil)
    end

    it "sends booleans, numbers, text, arrays and hashes as they are" do
      details = { "gift" => true, "express" => false, "items" => 3, "total" => 49.9, "plan" => "pro",
                  "skus" => %w[a-1 b-2], "address" => { "country" => "AR" } }
      client.track("checkout-completed", details: details)

      expect(details_reported_by_closing(client)).to eq(details)
    end

    it "sends a Time as its ISO 8601 text in UTC with milliseconds" do
      client.track("checkout-completed", details: { "paid_at" => Time.new(2026, 11, 15, 7, 30, 5.25r, "-03:00") })

      expect(details_reported_by_closing(client)).to eq("paid_at" => "2026-11-15T10:30:05.250Z")
    end

    it "leaves the Time it was given in its own offset" do
      paid_at = Time.new(2026, 11, 15, 7, 30, 5, "-03:00")

      client.track("checkout-completed", details: { "paid_at" => paid_at })

      expect(paid_at.utc_offset).to eq(-3 * 60 * 60)
      expect(paid_at.hour).to eq(7)
    end

    it "sends a frozen Time" do
      client.track("checkout-completed", details: { "paid_at" => Time.new(2026, 11, 15, 7, 30, 5, "-03:00").freeze })

      expect(details_reported_by_closing(client)).to eq("paid_at" => "2026-11-15T10:30:05.000Z")
    end

    it "sends a Float that is not finite as null" do
      client.track("checkout-completed", details: { "ratio" => Float::NAN })

      expect(details_reported_by_closing(client)).to eq("ratio" => nil)
    end

    it "sends empty details as an empty object" do
      client.track("checkout-completed", details: {})

      expect(details_reported_by_closing(client)).to eq({})
    end

    it "keeps the last of a String key and a Symbol key that name the same key" do
      client.track("checkout-completed", details: { "plan" => "basic", plan: "pro" })

      expect(details_reported_by_closing(client)).to eq("plan" => "pro")
    end

    it "leaves out details that hold a Date" do
      client.track("checkout-completed", details: { "paid_on" => Date.new(2026, 11, 15) })

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("details")
    end

    it "leaves out details with a key that is neither a String nor a Symbol" do
      client.track("checkout-completed", details: { 1 => "first" })

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("details")
    end

    it "leaves out details that are not a Hash" do
      client.track("checkout-completed", details: [%w[plan pro]])

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("details")
    end

    it "leaves out details that hold themselves" do
      details = { "plan" => "pro" }
      details["itself"] = details
      client.track("checkout-completed", details: details)

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("details")
    end

    it "reports details nested 100 levels deep" do
      client.track("checkout-completed", details: { "levels" => arrays_nested(98, around: []) })

      expect(details_reported_by_closing(client)).to eq("levels" => arrays_nested(98, around: []))
    end

    it "reports a value inside the 100th level" do
      client.track("checkout-completed", details: { "levels" => arrays_nested(99, around: 1) })

      expect(details_reported_by_closing(client)).to eq("levels" => arrays_nested(99, around: 1))
    end

    it "leaves out details nested 101 levels deep" do
      client.track("checkout-completed", details: { "levels" => arrays_nested(99, around: []) })

      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("details")
    end

    it "leaves out details of more values than 1,024 bytes of JSON can hold at once, however often they repeat" do
      repeated_array = [0] * 10_000
      details = { "repeats" => [repeated_array] * 1_000 }

      seconds_track_took = seconds_taken { client.track("checkout-completed", details: details) }

      expect(seconds_track_took).to be < 0.5
      expect(tracked_events_reported_by_closing(client).first.keys).not_to include("details")
    end
  end
end
