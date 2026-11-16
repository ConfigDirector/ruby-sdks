# frozen_string_literal: true

require "configdirector/testing"
require_relative "../support/elapsed_seconds"
require_relative "../support/recording_logger"
require_relative "../support/waiting"

RSpec.describe "A test client" do
  include ElapsedSeconds
  include Waiting

  let(:refusal_message) do
    "Connection failed with status: 401. Error: the test client failed this initialization. " \
      "This is an unrecoverable error, will not attempt to reconnect."
  end
  let(:logger) { RecordingLogger.new }
  let(:test_clients_created) { [] }

  after { test_clients_created.each { |test_client| test_client.client.close } }

  def test_client_serving(values = nil, **options)
    test_client = ConfigDirector::Testing.create_test_client(values, logger: logger, **options)
    test_clients_created << test_client
    test_client
  end

  it "serves its values to any context after init" do
    test_client = test_client_serving({ "new-checkout" => true, "max-items" => 20 })

    test_client.client.init

    expect(test_client.client.get_value("new-checkout", false, ConfigDirector::Context.new(id: "user-123"))).to be(true)
    expect(test_client.client.get_value("max-items", 0)).to eq(20)
  end

  it "serves a value as a match with no value ID and no variation" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.client.init

    evaluation = test_client.client.evaluate("new-checkout", false)

    expect(evaluation.value).to be(true)
    expect(evaluation.reason).to eq("found-match")
    expect(evaluation.value_id).to be_nil
    expect(evaluation.variation).to be_nil
  end

  it "gives each config the ID test-config: followed by its key" do
    test_client = test_client_serving({ "max-items" => 20 })
    test_client.client.init

    expect(test_client.client.get_all_configs.fetch("max-items")).to eq(
      ConfigDirector::ConfigState.new(id: "test-config:max-items", key: "max-items", type: "integer", value: "20")
    )
  end

  it "starts not ready, serving the in-code default value before init" do
    test_client = test_client_serving({ "new-checkout" => true })

    evaluation = test_client.client.evaluate("new-checkout", false)

    expect(test_client.client.ready?).to be(false)
    expect(evaluation.value).to be(false)
    expect(evaluation.reason).to eq("client-not-ready")
  end

  it "reads a Symbol config key as its name" do
    test_client = test_client_serving({ "new-checkout": true })
    test_client.set_value(:"max-items", 20)

    test_client.client.init

    expect(test_client.client.get_value("new-checkout", false)).to be(true)
    expect(test_client.client.get_value("max-items", 0)).to eq(20)
  end

  it "rejects a value the SDK cannot serve when it is created" do
    expect { test_client_serving({ "beta" => nil }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "Invalid value for 'beta': nil. Use true or false, an Integer, a Float, a String, a Hash or an Array."
    )
  end

  it "rejects values that are not a Hash when it is created" do
    expect { test_client_serving([["new-checkout", true]]) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError, "Invalid 'values' option of class Array. It must be a Hash."
    )
  end

  it "rejects a value the SDK cannot serve from set_value, changing nothing and delivering nothing" do
    test_client = test_client_serving({ "max-items" => 20 })
    test_client.client.init
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }

    expect { test_client.set_value("max-items", Float::NAN) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError, "Invalid value for 'max-items': NaN is not a finite number."
    )
    expect(test_client.client.get_value("max-items", 0)).to eq(20)
    expect(updates).to eq([])
  end

  it "rejects a config key of another class from set_value" do
    test_client = test_client_serving

    expect { test_client.set_value(42, true) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "Invalid config key of class Integer. A config key must be a String or a Symbol."
    )
  end

  it "rejects values from replace_values when one cannot be served, changing nothing and delivering nothing" do
    test_client = test_client_serving({ "max-items" => 20 })
    test_client.client.init
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }

    expect { test_client.replace_values({ "max-items" => 50, "plan" => :pro }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "Invalid value for 'plan': an object of class Symbol. " \
      "Use true or false, an Integer, a Float, a String, a Hash or an Array."
    )
    expect(test_client.client.get_value("max-items", 0)).to eq(20)
    expect(updates).to eq([])
  end

  it "rejects values given to replace_values that are not a Hash" do
    test_client = test_client_serving({ "max-items" => 20 })

    expect { test_client.replace_values(nil) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError, "Invalid 'values' option of class NilClass. It must be a Hash."
    )
  end

  it "delivers a value set while it is connected before set_value returns, naming only that key" do
    test_client = test_client_serving({ "new-checkout" => true, "max-items" => 20 })
    test_client.client.init
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }
    new_checkout_values = []
    test_client.client.watch("new-checkout", true) { |value| new_checkout_values << value }
    max_items_values = []
    test_client.client.watch("max-items", 0) { |value| max_items_values << value }

    returned = test_client.set_value("new-checkout", false)

    expect(returned).to be_nil
    expect(test_client.client.get_value("new-checkout", true)).to be(false)
    expect(updates).to eq([ConfigDirector::ConfigsUpdatedEvent.new(keys: ["new-checkout"], removed_keys: [])])
    expect(new_checkout_values).to eq([false])
    expect(max_items_values).to eq([])
  end

  it "delivers a value set from inside a watch after the change being handled" do
    test_client = test_client_serving({ "new-checkout" => false, "max-items" => 20 })
    test_client.client.init
    events = []
    test_client.client.on(:configs_updated) { |update| events << [:configs_updated, update.keys] }
    test_client.client.watch("new-checkout", false) do |value|
      test_client.set_value("max-items", 50) if value
      events << [:new_checkout_watch_returned, value]
    end
    test_client.client.watch("max-items", 0) { |value| events << [:max_items_watch, value] }

    test_client.set_value("new-checkout", true)

    expect(events).to eq(
      [
        [:configs_updated, ["new-checkout"]], [:new_checkout_watch_returned, true],
        [:configs_updated, ["max-items"]], [:max_items_watch, 50]
      ]
    )
  end

  it "calls client_ready during init before a change made from a configs_updated handler" do
    test_client = test_client_serving({ "new-checkout" => true })
    events = []
    test_client.client.on(:configs_updated) do |update|
      events << [:configs_updated, update.keys]
      test_client.set_value("max-items", 20) if update.keys == ["new-checkout"]
    end
    test_client.client.on(:client_ready) { events << [:client_ready] }

    test_client.client.init

    expect(events).to eq([[:configs_updated, ["new-checkout"]], [:client_ready], [:configs_updated, ["max-items"]]])
  end

  it "delivers its values again at a later init, without calling client_ready again" do
    test_client = test_client_serving({ "new-checkout" => true, "max-items" => 20 })
    test_client.client.init
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }
    ready_calls = []
    test_client.client.on(:client_ready) { ready_calls << :client_ready }

    test_client.client.init

    expect(updates).to eq([ConfigDirector::ConfigsUpdatedEvent.new(keys: %w[new-checkout max-items], removed_keys: [])])
    expect(ready_calls).to eq([])
  end

  it "delivers two values set from inside a watch in the order they were set" do
    test_client = test_client_serving({ "new-checkout" => false, "max-items" => 20 })
    test_client.client.init
    test_client.client.watch("new-checkout", false) do |value|
      next unless value

      test_client.set_value("max-items", 50)
      test_client.set_value("max-items", 80)
    end
    max_items_values = []
    test_client.client.watch("max-items", 0) { |value| max_items_values << value }

    test_client.set_value("new-checkout", true)

    expect(max_items_values).to eq([50, 80])
    expect(test_client.client.get_value("max-items", 0)).to eq(80)
  end

  it "delivers later changes after a watch raised an exception that is not a StandardError" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.client.init
    interrupting_watch = test_client.client.watch("new-checkout", true) { raise Interrupt }
    expect { test_client.set_value("new-checkout", false) }.to raise_error(Interrupt)
    interrupting_watch.close
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }

    test_client.set_value("new-checkout", true)

    expect(updates).to eq([ConfigDirector::ConfigsUpdatedEvent.new(keys: ["new-checkout"], removed_keys: [])])
  end

  it "leaves a value set on another thread during a delivery to the thread delivering, after the change it delivers" do
    test_client = test_client_serving({ "new-checkout" => false, "max-items" => 20 })
    test_client.client.init
    watch_entered = Queue.new
    watch_released = Queue.new
    test_client.client.watch("new-checkout", false) do
      watch_entered << :entered
      watch_released.pop
    end
    max_items_values = []
    test_client.client.watch("max-items", 0) { |value| max_items_values << value }
    delivering = Thread.new { test_client.set_value("new-checkout", true) }
    watch_entered.pop

    test_client.set_value("max-items", 50)
    values_when_set_value_returned = max_items_values.dup
    watch_released << :released
    delivering.join(5)

    expect(values_when_set_value_returned).to eq([])
    expect(max_items_values).to eq([50])
  end

  it "names the key and runs its watch when set_value gives the value the key already has" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.client.init
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }
    new_checkout_values = []
    test_client.client.watch("new-checkout", false) { |value| new_checkout_values << value }

    test_client.set_value("new-checkout", true)

    expect(updates).to eq([ConfigDirector::ConfigsUpdatedEvent.new(keys: ["new-checkout"], removed_keys: [])])
    expect(new_checkout_values).to eq([true])
  end

  it "stores a value set before init, delivers nothing, and serves it from init" do
    test_client = test_client_serving({ "new-checkout" => true })
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }

    test_client.set_value("max-items", 20)

    expect(updates).to eq([])
    test_client.client.init
    expect(test_client.client.get_value("max-items", 0)).to eq(20)
    expect(updates).to eq(
      [ConfigDirector::ConfigsUpdatedEvent.new(keys: %w[new-checkout max-items], removed_keys: [])]
    )
  end

  it "delivers the removal of a value as a full update before remove_value returns" do
    test_client = test_client_serving({ "new-checkout" => true, "max-items" => 20 })
    test_client.client.init
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }
    new_checkout_values = []
    test_client.client.watch("new-checkout", false) { |value| new_checkout_values << value }
    max_items_values = []
    test_client.client.watch("max-items", 0) { |value| max_items_values << value }

    returned = test_client.remove_value("new-checkout")

    evaluation = test_client.client.evaluate("new-checkout", false)
    expect(returned).to be_nil
    expect(evaluation.value).to be(false)
    expect(evaluation.reason).to eq("config-state-missing")
    expect(updates).to eq(
      [ConfigDirector::ConfigsUpdatedEvent.new(keys: ["max-items"], removed_keys: ["new-checkout"])]
    )
    expect(new_checkout_values).to eq([false])
    expect(max_items_values).to eq([20])
  end

  it "removes the key a Symbol names" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.client.init

    test_client.remove_value(:"new-checkout")

    expect(test_client.client.evaluate("new-checkout", false).reason).to eq("config-state-missing")
  end

  it "removes the key a String in another encoding names" do
    test_client = test_client_serving({ "café-banner" => true })
    test_client.client.init

    test_client.remove_value("café-banner".encode(Encoding::ISO_8859_1))

    expect(test_client.client.evaluate("café-banner", false).reason).to eq("config-state-missing")
  end

  it "removes nothing for a String that is not valid UTF-8 text, and still delivers a full update" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.client.init
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }

    test_client.remove_value("new-\xFFcheckout".b)

    expect(test_client.client.get_value("new-checkout", false)).to be(true)
    expect(updates).to eq([ConfigDirector::ConfigsUpdatedEvent.new(keys: ["new-checkout"], removed_keys: [])])
  end

  it "removes nothing for a blank key, and still delivers a full update" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.client.init
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }

    test_client.remove_value(" ")

    expect(test_client.client.get_value("new-checkout", false)).to be(true)
    expect(updates).to eq([ConfigDirector::ConfigsUpdatedEvent.new(keys: ["new-checkout"], removed_keys: [])])
  end

  it "rejects a key of another class from remove_value" do
    test_client = test_client_serving({ "new-checkout" => true })

    expect { test_client.remove_value(42) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "Invalid config key of class Integer. A config key must be a String or a Symbol."
    )
  end

  it "delivers the values given to replace_values as a full update before it returns" do
    test_client = test_client_serving({ "new-checkout" => true, "max-items" => 20 })
    test_client.client.init
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }

    returned = test_client.replace_values({ "max-items" => 50, "banner-text" => "Welcome back" })

    expect(returned).to be_nil
    expect(test_client.client.get_value("max-items", 0)).to eq(50)
    expect(test_client.client.get_value("banner-text", "Hello")).to eq("Welcome back")
    expect(test_client.client.evaluate("new-checkout", false).reason).to eq("config-state-missing")
    expect(updates).to eq(
      [ConfigDirector::ConfigsUpdatedEvent.new(keys: %w[max-items banner-text], removed_keys: ["new-checkout"])]
    )
  end

  it "fails the next init when fail_initialization is called before it, leaving the client not ready" do
    test_client = test_client_serving({ "new-checkout" => true })

    returned = test_client.fail_initialization
    init_seconds = seconds_taken { test_client.client.init }

    evaluation = test_client.client.evaluate("new-checkout", false)
    expect(returned).to be_nil
    expect(init_seconds).to be < 1
    expect(test_client.client.ready?).to be(false)
    expect(evaluation.value).to be(false)
    expect(evaluation.reason).to eq("client-not-ready")
  end

  it "logs one error line and calls connection_error with a connection error of status 401 when an init fails" do
    test_client = test_client_serving({ "new-checkout" => true })
    connection_errors = []
    test_client.client.on(:connection_error) { |event| connection_errors << event.error }
    test_client.fail_initialization

    test_client.client.init

    expect(logger.messages_at(:error)).to eq(["[InMemoryConnection] #{refusal_message}"])
    expect(logger.messages_at(:warn)).to eq([])
    expect(connection_errors.map(&:class)).to eq([ConfigDirector::ConfigDirectorConnectionError])
    expect(connection_errors.map(&:status)).to eq([401])
    expect(connection_errors.map(&:message)).to eq([refusal_message])
  end

  it "serves the values stored by then at the init that follows a failed one" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.fail_initialization
    test_client.client.init
    test_client.set_value("max-items", 20)

    test_client.client.init

    expect(test_client.client.ready?).to be(true)
    expect(test_client.client.get_value("new-checkout", false)).to be(true)
    expect(test_client.client.get_value("max-items", 0)).to eq(20)
  end

  it "calls connection_error at each failed init" do
    test_client = test_client_serving({ "new-checkout" => true })
    connection_errors = []
    test_client.client.on(:connection_error) { |event| connection_errors << event.error }

    test_client.fail_initialization
    test_client.client.init
    test_client.fail_initialization
    test_client.client.init

    expect(connection_errors.map(&:status)).to eq([401, 401])
  end

  it "keeps serving its values and stays ready when a later init fails" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.client.init
    test_client.fail_initialization

    test_client.client.init

    expect(test_client.client.ready?).to be(true)
    expect(test_client.client.get_value("new-checkout", false)).to be(true)
  end

  it "returns from a held init on another thread once complete_initialization delivers the values on its own thread" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 5)
    threads_calling_client_ready = []
    test_client.client.on(:client_ready) { threads_calling_client_ready << Thread.current }

    returned_from_the_hold = test_client.hold_initialization
    initializing = Thread.new { seconds_taken { test_client.client.init } }
    wait_up_to(5) { initializing.status == "sleep" }
    ready_while_held = test_client.client.ready?
    returned = test_client.complete_initialization

    expect(returned_from_the_hold).to be_nil
    expect(ready_while_held).to be(false)
    expect(returned).to be_nil
    expect(test_client.client.ready?).to be(true)
    expect(initializing.value).to be < 1
    expect(threads_calling_client_ready).to eq([Thread.current])
    expect(test_client.client.get_value("new-checkout", false)).to be(true)
    expect(logger.messages_at(:warn)).to eq([])
  end

  it "returns from a held init once the client_ready handlers of the values complete_initialization delivers ran" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 5)
    client_ready_handlers_ended = []
    test_client.client.on(:client_ready) do
      sleep(0.1)
      client_ready_handlers_ended << true
    end
    test_client.hold_initialization
    initializing = Thread.new do
      test_client.client.init
      [test_client.client.ready?, client_ready_handlers_ended.dup]
    end
    wait_up_to(5) { initializing.status == "sleep" }

    test_client.complete_initialization

    expect(initializing.value).to eq([true, [true]])
  end

  it "returns from a held later init once the watches of the values complete_initialization delivers ran" do
    test_client = test_client_serving({ "max-items" => 20 }, timeout: 5)
    test_client.client.init
    test_client.set_value("max-items", 50)
    max_items_values = []
    test_client.client.watch("max-items", 0) do |value|
      sleep(0.1)
      max_items_values << value
    end
    test_client.hold_initialization
    initializing = Thread.new do
      test_client.client.init
      max_items_values.dup
    end
    wait_up_to(5) { initializing.status == "sleep" }

    test_client.complete_initialization

    expect(initializing.value).to eq([50])
  end

  it "returns from a held init that fail_initialization fails once the error is logged and connection_error ran" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 5)
    connection_errors = []
    test_client.client.on(:connection_error) do |event|
      sleep(0.1)
      connection_errors << event.error
    end
    test_client.hold_initialization
    initializing = Thread.new do
      test_client.client.init
      [logger.messages_at(:error).length, connection_errors.length]
    end
    wait_up_to(5) { initializing.status == "sleep" }

    test_client.fail_initialization

    expect(initializing.value).to eq([1, 1])
  end

  it "returns from a held init at once when a watch raises an exception that is not a StandardError at completion" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 5)
    test_client.client.watch("new-checkout", false) { raise Interrupt }
    test_client.hold_initialization
    initializing = Thread.new { seconds_taken { test_client.client.init } }
    wait_up_to(5) { initializing.status == "sleep" }

    expect { test_client.complete_initialization }.to raise_error(Interrupt)
    expect(initializing.value).to be < 1
  end

  it "returns not ready from a held init at the timeout, logging the timeout warning" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 0.05)
    test_client.hold_initialization

    init_seconds = seconds_taken { test_client.client.init }

    expect(init_seconds).to be >= 0.05
    expect(test_client.client.ready?).to be(false)
    expect(logger.messages_at(:warn)).to eq(
      [
        "[ConfigDirectorClient] Timed out waiting for initialization after 0.05s. " \
        "Configs return the in-code default value until values arrive."
      ]
    )
  end

  it "cancels a hold when complete_initialization is called before init" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 5)
    test_client.hold_initialization
    test_client.complete_initialization

    init_seconds = seconds_taken { test_client.client.init }

    expect(init_seconds).to be < 1
    expect(test_client.client.ready?).to be(true)
  end

  it "does nothing at complete_initialization after a held init ended at the timeout" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 0.05)
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }
    test_client.hold_initialization
    test_client.client.init

    test_client.complete_initialization

    expect(test_client.client.ready?).to be(false)
    expect(updates).to eq([])
  end

  it "delivers nothing at complete_initialization while it is connected and nothing is held" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.client.init
    updates = []
    test_client.client.on(:configs_updated) { |update| updates << update }

    test_client.complete_initialization

    expect(updates).to eq([])
  end

  it "fails a held init on another thread at fail_initialization, calling connection_error on its own thread" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 5)
    threads_calling_connection_error = []
    test_client.client.on(:connection_error) { threads_calling_connection_error << Thread.current }
    test_client.hold_initialization
    initializing = Thread.new { seconds_taken { test_client.client.init } }
    wait_up_to(5) { initializing.status == "sleep" }

    returned = test_client.fail_initialization

    expect(returned).to be_nil
    expect(threads_calling_connection_error).to eq([Thread.current])
    expect(initializing.join(5).value).to be < 1
    expect(test_client.client.ready?).to be(false)
    expect(logger.messages_at(:error)).to eq(["[InMemoryConnection] #{refusal_message}"])
    expect(logger.messages_at(:warn)).to eq([])
  end

  it "fails the next init at fail_initialization after a held init ended at the timeout" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 0.05)
    connection_errors = []
    test_client.client.on(:connection_error) { |event| connection_errors << event.error }
    test_client.hold_initialization
    test_client.client.init

    test_client.fail_initialization
    errors_before_the_next_init = connection_errors.length
    test_client.client.init

    expect(errors_before_the_next_init).to eq(0)
    expect(connection_errors.map(&:status)).to eq([401])
    expect(test_client.client.ready?).to be(false)
  end

  it "keeps serving its values through a later init that is held until the timeout, logging no warning" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 0.2)
    test_client.client.init
    test_client.hold_initialization
    values_served_while_held = []

    initializing = Thread.new { seconds_taken { test_client.client.init } }
    wait_up_to(5) { initializing.status == "sleep" }
    values_served_while_held << test_client.client.get_value("new-checkout", false)

    expect(initializing.join(5).value).to be >= 0.2
    expect(values_served_while_held).to eq([true])
    expect(test_client.client.ready?).to be(true)
    expect(logger.messages_at(:warn)).to eq([])
  end

  it "logs the timeout warning at a held init that follows a failed one" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 0.05)
    test_client.fail_initialization
    test_client.client.init
    test_client.hold_initialization

    test_client.client.init

    expect(test_client.client.ready?).to be(false)
    expect(logger.messages_at(:warn)).to eq(
      [
        "[ConfigDirectorClient] Timed out waiting for initialization after 0.05s. " \
        "Configs return the in-code default value until values arrive."
      ]
    )
  end

  it "delivers at complete_initialization a value set while init is held" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 5)
    test_client.hold_initialization
    initializing = Thread.new { test_client.client.init }
    wait_up_to(5) { initializing.status == "sleep" }

    test_client.set_value("max-items", 20)
    value_while_held = test_client.client.get_value("max-items", 0)
    test_client.complete_initialization
    initializing.join(5)

    expect(value_while_held).to eq(0)
    expect(test_client.client.get_value("max-items", 0)).to eq(20)
  end

  it "cancels a hold set before init at replace_values" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 5)
    test_client.hold_initialization
    test_client.replace_values({ "max-items" => 20 })

    init_seconds = seconds_taken { test_client.client.init }

    expect(init_seconds).to be < 1
    expect(test_client.client.get_value("max-items", 0)).to eq(20)
  end

  it "cancels a failure set before init at replace_values" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.fail_initialization
    test_client.replace_values({ "max-items" => 20 })

    test_client.client.init

    expect(test_client.client.get_value("max-items", 0)).to eq(20)
    expect(logger.messages_at(:error)).to eq([])
  end

  it "waits for a held init up to the client's default timeout of 3 seconds when no timeout is given" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.hold_initialization

    init_seconds = seconds_taken { test_client.client.init }

    expect(init_seconds).to be >= 3
    expect(logger.messages_at(:warn)).to eq(
      [
        "[ConfigDirectorClient] Timed out waiting for initialization after 3s. " \
        "Configs return the in-code default value until values arrive."
      ]
    )
  end

  it "rejects a timeout of zero" do
    expect { test_client_serving({ "new-checkout" => true }, timeout: 0) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "Invalid timeout '0'. The timeout must be a positive number of seconds."
    )
  end

  it "rejects a timeout that is not a number" do
    expect { test_client_serving({ "new-checkout" => true }, timeout: "3") }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "Invalid timeout '3'. The timeout must be a positive number of seconds."
    )
  end

  it "rejects a logger that lacks a method of Ruby's Logger" do
    expect do
      ConfigDirector::Testing.create_test_client({ "new-checkout" => true }, logger: Object.new)
    end.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "Invalid logger of class Object. A logger must respond to debug, info, warn and error."
    )
  end

  it "writes warnings to standard error when no logger is given" do
    test_client = ConfigDirector::Testing.create_test_client({ "new-checkout" => true }, timeout: 0.05)
    test_clients_created << test_client
    test_client.hold_initialization

    expect { test_client.client.init }.to output(
      "[ConfigDirector:ruby-server-sdk] WARN: [ConfigDirectorClient] Timed out waiting for initialization after " \
      "0.05s. Configs return the in-code default value until values arrive.\n"
    ).to_stderr_from_any_process
  end

  it "logs an error for a context with an invalid kind on every read" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.client.init

    3.times { test_client.client.get_value("new-checkout", false, ConfigDirector::Context.new(kind: "Device")) }

    expect(logger.messages_at(:error).length).to eq(3)
    expect(logger.messages_at(:error)).to all(include("Device"))
  end

  it "starts no thread" do
    threads_before_the_test_client = Thread.list
    thread_starts = 0
    counting_thread_starts = TracePoint.new(:thread_begin) { thread_starts += 1 }

    counting_thread_starts.enable(target_thread: nil) do
      test_client = test_client_serving({ "new-checkout" => true })
      test_client.client.init
      test_client.set_value("new-checkout", false)
    end

    expect(thread_starts).to eq(0)
    expect(Thread.list).to eq(threads_before_the_test_client)
  end

  it "opens no socket" do
    GC.disable
    sockets_before_the_test_client = ObjectSpace.each_object(BasicSocket).count

    test_client = test_client_serving({ "new-checkout" => true })
    test_client.client.init
    test_client.set_value("new-checkout", false)

    expect(ObjectSpace.each_object(BasicSocket).count).to eq(sockets_before_the_test_client)
  ensure
    GC.enable
  end

  it "leaves a failure set before init in place at complete_initialization" do
    test_client = test_client_serving({ "new-checkout" => true })
    test_client.fail_initialization
    test_client.complete_initialization

    test_client.client.init

    expect(test_client.client.ready?).to be(false)
    expect(logger.messages_at(:error)).to eq(["[InMemoryConnection] #{refusal_message}"])
  end

  it "keeps an init that is already held waiting at replace_values, and completes it with the new values" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 5)
    test_client.hold_initialization
    initializing = Thread.new { test_client.client.init }
    wait_up_to(5) { initializing.status == "sleep" }

    test_client.replace_values({ "max-items" => 20 })
    ready_after_the_replacement = test_client.client.ready?
    test_client.complete_initialization
    initializing.join(5)

    expect(ready_after_the_replacement).to be(false)
    expect(test_client.client.get_value("max-items", 0)).to eq(20)
    expect(test_client.client.evaluate("new-checkout", false).reason).to eq("config-state-missing")
  end

  it "returns from a close called while another thread's init is held once that init returns" do
    test_client = test_client_serving({ "new-checkout" => true }, timeout: 0.3)
    test_client.hold_initialization
    initializing = Thread.new { test_client.client.init }
    wait_up_to(5) { initializing.status == "sleep" }

    close_seconds = seconds_taken { test_client.client.close }

    expect(close_seconds).to be >= 0.2
    expect(initializing.join(5)).to eq(initializing)
    expect(test_client.client.closed?).to be(true)
  end

  describe "tracked events" do
    it "records an event tracked through its client with its context, value and details" do
      test_client = test_client_serving

      test_client.client.track(
        "checkout-completed", ConfigDirector::Context.new(id: "user-123"), value: 49.9, details: { "plan" => "pro" }
      )

      expect(test_client.tracked_events).to eq(
        [
          ConfigDirector::Testing::TrackedEvent.new(
            name: "checkout-completed", context: ConfigDirector::Context.new(id: "user-123"), value: 49.9,
            details: { "plan" => "pro" }
          )
        ]
      )
      expect(test_client.tracked_events.first.name).to eq("checkout-completed")
      expect(test_client.tracked_events.first.context).to eq(ConfigDirector::Context.new(id: "user-123"))
      expect(test_client.tracked_events.first.value).to eq(49.9)
      expect(test_client.tracked_events.first.details).to eq("plan" => "pro")
    end

    it "records an event that cannot be changed" do
      test_client = test_client_serving

      test_client.client.track("checkout-completed", details: { "cart" => { "skus" => ["a-1"] } })

      tracked_event = test_client.tracked_events.first
      expect(tracked_event).to be_frozen
      expect(tracked_event.name).to be_frozen
      expect(tracked_event.details.fetch("cart").fetch("skus")).to be_frozen
    end

    it "records events in the order they were tracked, without a context, value or details that were not given" do
      test_client = test_client_serving

      test_client.client.track("cart-viewed")
      test_client.client.track("checkout-completed")

      expect(test_client.tracked_events).to eq(
        [
          ConfigDirector::Testing::TrackedEvent.new(name: "cart-viewed"),
          ConfigDirector::Testing::TrackedEvent.new(name: "checkout-completed")
        ]
      )
      expect(test_client.tracked_events.first.context).to be_nil
      expect(test_client.tracked_events.first.value).to be_nil
      expect(test_client.tracked_events.first.details).to be_nil
    end

    it "returns the same list on every call, which grows as events are tracked" do
      test_client = test_client_serving
      tracked_events = test_client.tracked_events

      test_client.client.track("checkout-completed")

      expect(test_client.tracked_events).to equal(tracked_events)
      expect(tracked_events.map(&:name)).to eq(["checkout-completed"])
    end

    it "lets a test empty its list" do
      test_client = test_client_serving
      test_client.client.track("cart-viewed")

      test_client.tracked_events.clear
      test_client.client.track("checkout-completed")

      expect(test_client.tracked_events.map(&:name)).to eq(["checkout-completed"])
    end

    it "does not record an event with an empty name, logging the warning each time without the batch sentence" do
      test_client = test_client_serving

      2.times { test_client.client.track("") }

      expect(test_client.tracked_events).to eq([])
      expect(logger.messages_at(:warn)).to eq(
        [
          "[ConfigDirectorClient] A tracked event was not reported because its name does not have 1 to 150 " \
          "characters.",
          "[ConfigDirectorClient] A tracked event was not reported because its name does not have 1 to 150 " \
          "characters."
        ]
      )
    end

    it "records an event without the value and details the SDK would leave out, logging each warning" do
      test_client = test_client_serving

      test_client.client.track("checkout-completed", value: Float::NAN, details: { 1 => "first" })

      expect(test_client.tracked_events).to eq([ConfigDirector::Testing::TrackedEvent.new(name: "checkout-completed")])
      expect(logger.messages_at(:warn)).to eq(
        [
          "[ConfigDirectorClient] A tracked event was reported without its value because the value is not a " \
          "finite number.",
          "[ConfigDirectorClient] A tracked event was reported without its details because they are not an object, " \
          "have more than 20 top-level keys, are larger than 1024 bytes as JSON, or cannot be written as JSON."
        ]
      )
    end

    it "records the details as the SDK sends them" do
      test_client = test_client_serving

      test_client.client.track(
        "checkout-completed",
        details: { plan: :pro, paid_at: Time.utc(2026, 11, 15, 10, 30), ratio: Float::INFINITY, total: 50.0 }
      )

      expect(test_client.tracked_events.first.details).to eq(
        "plan" => "pro", "paid_at" => "2026-11-15T10:30:00.000Z", "ratio" => nil, "total" => 50
      )
      expect(test_client.tracked_events.first.details.fetch("total")).to eql(50)
    end

    it "records an event whose context kind is invalid without the context" do
      test_client = test_client_serving

      test_client.client.track("checkout-completed", ConfigDirector::Context.new(id: "device-1", kind: "Device"))

      expect(test_client.tracked_events).to eq([ConfigDirector::Testing::TrackedEvent.new(name: "checkout-completed")])
    end

    it "records more than 1,000 events" do
      test_client = test_client_serving

      1_001.times { |number| test_client.client.track("event-#{number}") }

      expect(test_client.tracked_events.length).to eq(1_001)
    end

    it "records nothing once its client is closed" do
      test_client = test_client_serving
      test_client.client.close

      test_client.client.track("checkout-completed")

      expect(test_client.tracked_events).to eq([])
    end

    it "keeps what it recorded at replace_values" do
      test_client = test_client_serving
      test_client.client.track("checkout-completed")

      test_client.replace_values({ "new-checkout" => true })

      expect(test_client.tracked_events.map(&:name)).to eq(["checkout-completed"])
    end
  end
end
