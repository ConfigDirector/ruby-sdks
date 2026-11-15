# frozen_string_literal: true

require_relative "../support/recording_logger"
require_relative "../support/sdk_server_serving_the_sample_configs"

RSpec.describe "A client's events" do
  include_context "with an SDK server that serves the sample configs"

  let(:logger) { RecordingLogger.new }

  def client_with(hooks = ConfigDirector::ClientHooks.new)
    client_of_the_sample_configs(logger: logger, hooks: hooks)
  end

  def evaluated_keys_recorder(evaluated_keys)
    ->(event) { evaluated_keys << event.evaluation.key }
  end

  def evaluated_keys_recorder_class
    Class.new do
      attr_reader :evaluated_keys

      def initialize
        @evaluated_keys = []
      end

      def record(event)
        @evaluated_keys << event.evaluation.key
      end
    end
  end

  it "delivers client_ready during init to the hooks before the on handlers" do
    deliveries = []
    client = client_with(ConfigDirector::ClientHooks.new(client_ready: -> { deliveries << :hook }))
    client.on(:client_ready) { deliveries << :handler }

    client.init

    expect(deliveries).to eq(%i[hook handler])
  end

  it "names every config the payload delivered in configs_updated, in the payload's order" do
    updates = []
    client = client_with
    client.on(:configs_updated) { |update| updates << update }

    client.init

    expect(updates).to eq(
      [ConfigDirector::ConfigsUpdatedEvent.new(
        keys: %w[temporary-feature-flag permanent-kill-switch integer-config day-of-the-week-config
                 json-value-config json-list-config float-config config-without-a-value malformed-json-config],
        removed_keys: []
      )]
    )
  end

  it "delivers the evaluation of evaluate to config_evaluated before the read returns" do
    evaluated = []
    client = client_with
    client.init
    client.on(:config_evaluated) { |event| evaluated << event }

    client.evaluate("integer-config", 10)

    expect(evaluated).to eq(
      [ConfigDirector::ConfigEvaluatedEvent.new(
        evaluation: ConfigDirector::ConfigEvaluation.new(
          key: "integer-config", value: 42, default_value: false, reason: "found-match", value_id: "value-integer-42"
        )
      )]
    )
  end

  it "calls an object that responds to call as a handler" do
    evaluated_keys = []
    client = client_with
    client.on(:config_evaluated, evaluated_keys_recorder(evaluated_keys))

    client.get_value("integer-config", 10)

    expect(evaluated_keys).to eq(["integer-config"])
  end

  it "runs a handler registered twice twice" do
    evaluated_keys = []
    handler = evaluated_keys_recorder(evaluated_keys)
    client = client_with
    client.on(:config_evaluated, handler)
    client.on(:config_evaluated, handler)

    client.get_value("integer-config", 10)

    expect(evaluated_keys).to eq(%w[integer-config integer-config])
  end

  it "raises when on is given both a handler and a block" do
    client = client_with

    expect { client.on(:config_evaluated, ->(_event) {}) { |_event| nil } }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises when on is given neither a handler nor a block" do
    client = client_with

    expect { client.on(:config_evaluated) }.to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises when on is given a handler that does not respond to call" do
    client = client_with

    expect { client.on(:config_evaluated, "record") }.to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises when on is given an event name it does not know" do
    client = client_with

    expect { client.on("config_evaluated") { |_event| nil } }
      .to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "raises when off is given an event name it does not know" do
    client = client_with

    expect { client.off(:config_evaluation) }.to raise_error(ConfigDirector::ConfigDirectorValidationError)
  end

  it "removes one registration of a handler registered twice with off" do
    evaluated_keys = []
    handler = evaluated_keys_recorder(evaluated_keys)
    client = client_with
    client.on(:config_evaluated, handler)
    client.on(:config_evaluated, handler)

    client.off(:config_evaluated, handler)
    client.get_value("integer-config", 10)

    expect(evaluated_keys).to eq(["integer-config"])
  end

  it "removes a method registered as a handler when off is given the same method" do
    recorder = evaluated_keys_recorder_class.new
    client = client_with
    client.on(:config_evaluated, recorder.method(:record))

    client.off(:config_evaluated, recorder.method(:record))
    client.get_value("integer-config", 10)

    expect(recorder.evaluated_keys).to be_empty
  end

  it "removes every handler of the event, and only of that event, when off is given no handler" do
    deliveries = []
    client = client_with
    client.on(:config_evaluated) { deliveries << :first_evaluated_handler }
    client.on(:config_evaluated) { deliveries << :second_evaluated_handler }
    client.on(:client_ready) { deliveries << :ready_handler }

    client.off(:config_evaluated)
    client.init
    client.get_value("integer-config", 10)

    expect(deliveries).to eq([:ready_handler])
  end

  it "removes only the registration whose subscription is closed" do
    evaluated_keys = []
    handler = evaluated_keys_recorder(evaluated_keys)
    client = client_with
    first_subscription = client.on(:config_evaluated, handler)
    client.on(:config_evaluated, handler)

    first_subscription.close
    client.get_value("integer-config", 10)

    expect(evaluated_keys).to eq(["integer-config"])
  end

  it "keeps a later registration of the same handler when an earlier subscription is closed" do
    evaluated_keys = []
    handler = evaluated_keys_recorder(evaluated_keys)
    client = client_with
    subscription = client.on(:config_evaluated, handler)
    client.off(:config_evaluated, handler)
    client.on(:config_evaluated, handler)

    subscription.close
    client.get_value("integer-config", 10)

    expect(evaluated_keys).to eq(["integer-config"])
  end

  it "reports a subscription as not closed before close is called on it" do
    client = client_with

    subscription = client.on(:config_evaluated) { |_event| nil }

    expect(subscription.closed?).to be(false)
  end

  it "reports a subscription as closed once close is called on it" do
    client = client_with
    subscription = client.on(:config_evaluated) { |_event| nil }

    subscription.close

    expect(subscription.closed?).to be(true)
  end

  it "delivers configs_updated, then the watches, then client_ready" do
    deliveries = []
    client = client_with
    client.on(:client_ready) { deliveries << :client_ready }
    client.watch("integer-config", 10) { |_value| deliveries << :watch }
    client.on(:configs_updated) { |_update| deliveries << :configs_updated }

    client.init

    expect(deliveries).to eq(%i[configs_updated watch client_ready])
  end

  it "delivers the evaluation of get_value to config_evaluated" do
    evaluated = []
    client = client_with
    client.init
    client.on(:config_evaluated) { |event| evaluated << event.evaluation }

    client.get_value("day-of-the-week-config", "Sunday")

    expect(evaluated).to eq(
      [ConfigDirector::ConfigEvaluation.new(
        key: "day-of-the-week-config", value: "Monday", default_value: false, reason: "found-match",
        value_id: "value-monday"
      )]
    )
  end

  it "delivers the in-code default value of a read before init to config_evaluated" do
    evaluated = []
    client = client_with
    client.on(:config_evaluated) { |event| evaluated << event.evaluation }

    client.get_value("integer-config", 10)

    expect(evaluated).to eq(
      [ConfigDirector::ConfigEvaluation.new(
        key: "integer-config", value: 10, default_value: true, reason: "client-not-ready"
      )]
    )
  end

  it "delivers the evaluation of each watch to config_evaluated" do
    evaluated = []
    client = client_with
    client.watch("float-config", 1.5) { |_value| nil }
    client.on(:config_evaluated) { |event| evaluated << event.evaluation }

    client.init

    expect(evaluated).to eq(
      [ConfigDirector::ConfigEvaluation.new(
        key: "float-config", value: 26.0, default_value: false, reason: "found-match", value_id: "value-float-26"
      )]
    )
  end

  it "delivers nothing to config_evaluated for get_all_configs" do
    evaluated = []
    client = client_with
    client.init
    client.on(:config_evaluated) { |event| evaluated << event }

    client.get_all_configs

    expect(evaluated).to be_empty
  end

  it "registers every hook of an Array in the order given" do
    deliveries = []
    client = client_with(
      ConfigDirector::ClientHooks.new(
        client_ready: [-> { deliveries << :first_hook }, -> { deliveries << :second_hook }]
      )
    )

    client.init

    expect(deliveries).to eq(%i[first_hook second_hook])
  end

  it "skips a hook that does not respond to call with one warning and registers the others" do
    deliveries = []
    client = client_with(
      ConfigDirector::ClientHooks.new(configs_updated: ["record", ->(_update) { deliveries << :hook }])
    )

    client.init

    expect(deliveries).to eq([:hook])
    expect(logger.messages_at(:warn).length).to eq(1)
  end

  it "skips a single hook that does not respond to call with one warning" do
    client = client_with(ConfigDirector::ClientHooks.new(client_ready: "record"))

    client.init

    expect(client.ready?).to be(true)
    expect(logger.messages_at(:warn).length).to eq(1)
  end

  it "logs a handler that raises once, still runs the next handler and still returns the read" do
    deliveries = []
    client = client_with
    client.init
    client.on(:config_evaluated) { |_event| raise "handler failure" }
    client.on(:config_evaluated) { |_event| deliveries << :next_handler }

    value = client.get_value("integer-config", 10)

    expect(value).to eql(42)
    expect(deliveries).to eq([:next_handler])
    expect(logger.messages_at(:error).length).to eq(1)
  end

  it "lets an error that is not a StandardError out of a handler" do
    client = client_with
    client.on(:config_evaluated) { |_event| raise Interrupt }

    expect { client.get_value("integer-config", 10) }.to raise_error(Interrupt)
  end

  it "logs a watch that raises once and still delivers to the next watch" do
    values = []
    client = client_with
    client.watch("integer-config", 10) { |_value| raise "watch failure" }
    client.watch("integer-config", 10) { |value| values << value }

    client.init

    expect(values).to eq([42])
    expect(logger.messages_at(:error).length).to eq(1)
  end

  it "serves a read made from inside configs_updated" do
    values = []
    client = client_with
    client.on(:configs_updated) { |_update| values << client.get_value("integer-config", 10) }

    client.init

    expect(values).to eq([42])
    expect(logger.messages_at(:error)).to be_empty
  end

  it "delivers nothing after close to the handlers and hooks registered before it" do
    deliveries = []
    client = client_with(ConfigDirector::ClientHooks.new(config_evaluated: ->(_event) { deliveries << :hook }))
    client.on(:config_evaluated) { |_event| deliveries << :handler }

    client.close
    client.get_value("integer-config", 10)

    expect(deliveries).to be_empty
  end

  it "returns nil from off without a handler" do
    client = client_with
    client.on(:config_evaluated) { |_event| nil }

    expect(client.off(:config_evaluated)).to be_nil
  end

  it "returns nil from off with a handler" do
    handler = ->(_event) {}
    client = client_with
    client.on(:config_evaluated, handler)

    expect(client.off(:config_evaluated, handler)).to be_nil
  end

  it "returns nil from closing a subscription" do
    client = client_with
    subscription = client.on(:config_evaluated) { |_event| nil }

    expect(subscription.close).to be_nil
  end

  it "closes the client from a client_ready handler during init" do
    client = client_with
    client.on(:client_ready) { client.close }

    client.init

    expect(client.closed?).to be(true)
    expect(logger.messages_at(:error)).to be_empty
  end
end
