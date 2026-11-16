# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tmpdir"
require_relative "../support/client_of_the_scripted_sdk_server"

RSpec.describe "A client in offline mode" do
  include_context "with a client of the scripted SDK server"

  let(:folder) { Dir.mktmpdir }

  after { FileUtils.remove_entry(folder) }

  def file_holding(json_text, name: "flags.json")
    path = File.join(folder, name)
    File.binwrite(path, json_text)
    path
  end

  def offline_client(**connection_options)
    client = ConfigDirector.create_client(
      connection: ConfigDirector::ConnectionOptions.new(mode: "offline", **connection_options), logger: logger
    )
    clients_created << client
    client
  end

  it "serves a boolean value to any context, found with no value ID and no variation" do
    client = offline_client(values: { "new-checkout" => true })
    client.init

    evaluation = client.evaluate("new-checkout", false, ConfigDirector::Context.new(id: "user-123"))

    expect(evaluation.value).to be(true)
    expect(evaluation.reason).to eq("found-match")
    expect(evaluation.value_id).to be_nil
    expect(evaluation.variation).to be_nil
    expect(client.get_value("new-checkout", false)).to be(true)
  end

  it "serves an Integer as an integer config whose ID is the key behind offline:" do
    client = offline_client(values: { "max-items" => 20 })
    client.init

    expect(client.get_value("max-items", 0)).to eq(20)
    expect(client.get_all_configs.fetch("max-items")).to eq(
      ConfigDirector::ConfigState.new(id: "offline:max-items", key: "max-items", type: "integer", value: "20")
    )
  end

  it "serves a Float as a float config in plain decimal text" do
    client = offline_client(values: { "discount-rate" => 2.5 })
    client.init

    expect(client.get_value("discount-rate", 0.0)).to eq(2.5)
    expect(client.get_all_configs.fetch("discount-rate")).to eq(
      ConfigDirector::ConfigState.new(id: "offline:discount-rate", key: "discount-rate", type: "float", value: "2.5")
    )
  end

  it "writes a whole Float without a fraction" do
    client = offline_client(values: { "discount-rate" => 25.0 })
    client.init

    expect(client.get_all_configs.fetch("discount-rate").value).to eq("25")
    expect(client.get_value("discount-rate", 0.0)).to eq(25.0)
  end

  it "writes a Float with a negative exponent as plain decimal text" do
    client = offline_client(values: { "error-budget" => -1.5e-7 })
    client.init

    expect(client.get_all_configs.fetch("error-budget").value).to eq("-0.00000015")
    expect(client.get_value("error-budget", 0.0)).to eq(-1.5e-7)
  end

  it "writes a Float with a positive exponent as plain decimal text" do
    client = offline_client(values: { "request-budget" => 1.25e20 })
    client.init

    expect(client.get_all_configs.fetch("request-budget").value).to eq("125000000000000000000")
    expect(client.get_value("request-budget", 0.0)).to eq(1.25e20)
  end

  it "serves a String as a string config" do
    client = offline_client(values: { "banner-text" => "Welcome back" })
    client.init

    expect(client.get_value("banner-text", "Hello")).to eq("Welcome back")
    expect(client.get_all_configs.fetch("banner-text")).to eq(
      ConfigDirector::ConfigState.new(
        id: "offline:banner-text", key: "banner-text", type: "string", value: "Welcome back"
      )
    )
  end

  it "serves a Hash as a JSON config in compact JSON, with each Symbol key written as its name" do
    client = offline_client(values: { "checkout-limits" => { max_items: 20, "regions" => %w[eu us], coupon: nil } })
    client.init

    expect(client.get_value("checkout-limits", {})).to eq(
      { "max_items" => 20, "regions" => %w[eu us], "coupon" => nil }
    )
    expect(client.get_all_configs.fetch("checkout-limits")).to eq(
      ConfigDirector::ConfigState.new(
        id: "offline:checkout-limits", key: "checkout-limits", type: "json",
        value: '{"max_items":20,"regions":["eu","us"],"coupon":null}'
      )
    )
  end

  it "serves an Array as a JSON config in compact JSON" do
    client = offline_client(values: { "shipping-regions" => ["eu", 1.5, nil, { "code" => "us" }] })
    client.init

    expect(client.get_value("shipping-regions", [])).to eq(["eu", 1.5, nil, { "code" => "us" }])
    expect(client.get_all_configs.fetch("shipping-regions")).to eq(
      ConfigDirector::ConfigState.new(
        id: "offline:shipping-regions", key: "shipping-regions", type: "json", value: '["eu",1.5,null,{"code":"us"}]'
      )
    )
  end

  it "reads a Symbol config key as its name" do
    client = offline_client(values: { "new-checkout": true })
    client.init

    expect(client.get_value("new-checkout", false)).to be(true)
    expect(client.get_all_configs.fetch("new-checkout").id).to eq("offline:new-checkout")
  end

  it "rejects a nil value when the client is created" do
    expect { offline_client(values: { "beta" => nil }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'beta': nil. " \
      "Use true or false, an Integer, a Float, a String, a Hash or an Array."
    )
  end

  it "rejects a Float that is not finite when the client is created" do
    expect { offline_client(values: { "discount-rate" => Float::INFINITY }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'discount-rate': Infinity is not a finite number."
    )
  end

  it "rejects a Symbol value when the client is created" do
    expect { offline_client(values: { "plan" => :pro }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'plan': an object of class Symbol. " \
      "Use true or false, an Integer, a Float, a String, a Hash or an Array."
    )
  end

  it "rejects a blank config key when the client is created" do
    expect { offline_client(values: { " " => true }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid config key. The key of a value cannot be empty."
    )
  end

  it "rejects a config key that is neither a String nor a Symbol when the client is created" do
    expect { offline_client(values: { 42 => true }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid config key of class Integer. " \
      "A config key must be a String or a Symbol."
    )
  end

  it "rejects a config key that is a list holding itself when the client is created" do
    key_holding_itself = ["new-checkout"]
    key_holding_itself << key_holding_itself

    expect { offline_client(values: { key_holding_itself => true }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid config key of class Array. " \
      "A config key must be a String or a Symbol."
    )
  end

  it "rejects a config key given both as a String and as a Symbol when the client is created" do
    expect { offline_client(values: { "new-checkout" => true, "new-checkout": false }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. The config key 'new-checkout' is given twice, " \
      "as a String and as a Symbol."
    )
  end

  it "rejects an object of another class inside a JSON value, naming where it is" do
    expect { offline_client(values: { "checkout-limits" => { "items" => [1, 2, Time.at(0)] } }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'checkout-limits' at 'items[2]': an object of " \
      "class Time cannot be encoded as JSON. JSON contents can hold true and false, Integers, finite Floats, " \
      "Strings, nil, Arrays and Hashes with String or Symbol keys."
    )
  end

  it "rejects a Symbol inside a JSON value" do
    expect { offline_client(values: { "checkout-limits" => { "plan" => :pro } }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'checkout-limits' at 'plan': an object of " \
      "class Symbol cannot be encoded as JSON. JSON contents can hold true and false, Integers, finite Floats, " \
      "Strings, nil, Arrays and Hashes with String or Symbol keys."
    )
  end

  it "rejects a Float that is not finite inside a JSON value" do
    expect { offline_client(values: { "shipping-regions" => [Float::NAN] }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'shipping-regions' at '[0]': NaN is not a " \
      "finite number. JSON contents can hold true and false, Integers, finite Floats, Strings, nil, Arrays and " \
      "Hashes with String or Symbol keys."
    )
  end

  it "rejects a Hash key inside a JSON value that is neither a String nor a Symbol" do
    expect { offline_client(values: { "checkout-limits" => { "tiers" => { 1 => "basic" } } }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'checkout-limits' at 'tiers': a key of class " \
      "Integer cannot be encoded as JSON. JSON contents can hold true and false, Integers, finite Floats, " \
      "Strings, nil, Arrays and Hashes with String or Symbol keys."
    )
  end

  it "rejects a Hash key inside a JSON value given both as a String and as a Symbol" do
    expect { offline_client(values: { "checkout-limits" => { "plan" => "pro", plan: "basic" } }) }
      .to raise_error(
        ConfigDirector::ConfigDirectorValidationError,
        "The offline values could not be loaded. Invalid value for 'checkout-limits': the key 'plan' is given " \
        "twice, as a String and as a Symbol."
      )
  end

  it "serves a JSON value nested 100 levels deep" do
    nested_100_levels_deep = (1..99).reduce([]) { |nested, _level| [nested] }
    client = offline_client(values: { "deep-config" => nested_100_levels_deep })
    client.init

    expect(client.get_value("deep-config", [])).to eq(nested_100_levels_deep)
  end

  it "rejects a JSON value nested deeper than 100 levels" do
    nested_101_levels_deep = (1..100).reduce([]) { |nested, _level| [nested] }

    expect { offline_client(values: { "deep-config" => nested_101_levels_deep }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'deep-config': nesting of 101 is too deep."
    )
  end

  it "rejects a JSON value nested 100,000 levels deep" do
    nested_100_000_levels_deep = (1..99_999).reduce([]) { |nested, _level| [nested] }

    expect { offline_client(values: { "deep-config" => nested_100_000_levels_deep }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'deep-config': nesting of 101 is too deep."
    )
  end

  it "rejects a JSON value that holds itself" do
    value_holding_itself = { "limits" => [] }
    value_holding_itself.fetch("limits") << value_holding_itself

    expect { offline_client(values: { "deep-config" => value_holding_itself }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'deep-config': nesting of 101 is too deep."
    )
  end

  it "serves a String in another encoding as UTF-8 text" do
    client = offline_client(values: { "motto" => "Café".encode("ISO-8859-1") })
    client.init

    expect(client.get_value("motto", "")).to eq("Café")
  end

  it "reads a config key in another encoding as UTF-8 text" do
    client = offline_client(values: { "café".encode("ISO-8859-1") => true })
    client.init

    expect(client.get_value("café", false)).to be(true)
  end

  it "reads a binary String whose bytes are UTF-8 text as that text" do
    client = offline_client(values: { "motto" => "Café".b })
    client.init

    expect(client.get_value("motto", "")).to eq("Café")
  end

  it "rejects two config keys that name the same config in two encodings" do
    expect { offline_client(values: { "café" => true, "café".encode("ISO-8859-1") => false }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. The config key 'café' is given twice, in two encodings."
    )
  end

  it "rejects a String whose bytes are not valid UTF-8 when the client is created" do
    expect { offline_client(values: { "motto" => "Caf\xE9" }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'motto': the String is not valid UTF-8 text."
    )
  end

  it "rejects a binary String that cannot be read as UTF-8 when the client is created" do
    expect { offline_client(values: { "motto" => "Caf\xE9".b }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'motto': the String is not valid UTF-8 text."
    )
  end

  it "rejects a String inside a JSON value whose bytes are not valid UTF-8" do
    expect { offline_client(values: { "checkout-limits" => { "name" => "Caf\xE9" } }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'checkout-limits' at 'name': the String is not " \
      "valid UTF-8 text."
    )
  end

  it "rejects a Hash key inside a JSON value whose bytes are not valid UTF-8" do
    expect { offline_client(values: { "checkout-limits" => { "tiers" => { "caf\xE9" => 1 } } }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid value for 'checkout-limits' at 'tiers': a key is not " \
      "valid UTF-8 text."
    )
  end

  it "rejects a config key whose bytes are not valid UTF-8 when the client is created" do
    expect { offline_client(values: { "caf\xE9" => true }) }.to raise_error(
      ConfigDirector::ConfigDirectorValidationError,
      "The offline values could not be loaded. Invalid config key. The key of a value is not valid UTF-8 text."
    )
  end

  it "serves the values of a JSON file" do
    client = offline_client(file: file_holding('{"new-checkout": true, "max-items": 20}'))
    client.init

    expect(client.get_value("new-checkout", false)).to be(true)
    expect(client.get_value("max-items", 0)).to eq(20)
  end

  it "serves a number written with a fraction in the file as a float config" do
    client = offline_client(file: file_holding('{"discount-rate": 25.0}'))
    client.init

    expect(client.get_all_configs.fetch("discount-rate")).to eq(
      ConfigDirector::ConfigState.new(id: "offline:discount-rate", key: "discount-rate", type: "float", value: "25")
    )
  end

  it "reads a file given as a Pathname" do
    client = offline_client(file: Pathname.new(file_holding('{"new-checkout": true}')))
    client.init

    expect(client.get_value("new-checkout", false)).to be(true)
  end

  it "reads a relative path from the working directory" do
    file_holding('{"new-checkout": true}')
    client = offline_client(file: "flags.json")

    Dir.chdir(folder) { client.init }

    expect(client.get_value("new-checkout", false)).to be(true)
  end

  it "reads a file whose name starts with a pipe as a file, running nothing", unless: Gem.win_platform? do
    file_holding('{"banner-text": "read from the file"}', name: "|echo")
    client = offline_client(file: "|echo")

    Dir.chdir(folder) { client.init }

    expect(client.get_value("banner-text", "")).to eq("read from the file")
  end

  it "takes the last value of a key the file gives twice" do
    client = offline_client(file: file_holding('{"max-items": 20, "max-items": 30}'))
    client.init

    expect(client.get_value("max-items", 0)).to eq(30)
  end

  it "raises the initialization error from init for a file that does not exist, and stays not ready" do
    missing_path = File.join(folder, "missing.json")
    client = offline_client(file: missing_path)

    expect { client.init }.to raise_error(
      ConfigDirector::ConfigDirectorInitializationError,
      "The offline values file '#{missing_path}' could not be read: No such file or directory @ rb_sysopen - " \
      "#{missing_path}"
    )
    expect(client.ready?).to be(false)
  end

  it "raises the initialization error from init for a path that holds a NUL byte" do
    client = offline_client(file: "flags\0.json")

    expect { client.init }.to raise_error(
      ConfigDirector::ConfigDirectorInitializationError,
      "The offline values file 'flags\0.json' could not be read: path name contains null byte"
    )
  end

  it "raises the initialization error from init for a file that is not JSON" do
    path = file_holding("new-checkout: true")
    client = offline_client(file: path)

    expect { client.init }.to raise_error(
      ConfigDirector::ConfigDirectorInitializationError,
      /\AThe offline values file '#{Regexp.escape(path)}' is not valid JSON: ./
    )
    expect(client.ready?).to be(false)
  end

  it "raises the initialization error from init for a file that holds a JSON array" do
    path = file_holding('[{"new-checkout": true}]')
    client = offline_client(file: path)

    expect { client.init }.to raise_error(
      ConfigDirector::ConfigDirectorInitializationError,
      "The offline values file '#{path}' must hold a JSON object with one value per config key, but holds an array."
    )
  end

  it "raises the initialization error from init for a file that holds a value the SDK cannot serve" do
    path = file_holding('{"beta": null}')
    client = offline_client(file: path)

    expect { client.init }.to raise_error(
      ConfigDirector::ConfigDirectorInitializationError,
      "The offline values file '#{path}' could not be loaded. Invalid value for 'beta': nil. " \
      "Use true or false, an Integer, a Float, a String, a Hash or an Array."
    )
  end

  it "raises the initialization error from init for a file that is not UTF-8 text" do
    path = file_holding("{\"motto\": \"Caf\xE9\"}".b)
    client = offline_client(file: path)

    expect { client.init }.to raise_error(
      ConfigDirector::ConfigDirectorInitializationError,
      "The offline values file '#{path}' is not valid JSON: the text is not valid UTF-8."
    )
  end

  it "raises the initialization error from init for a file that starts with a byte order mark" do
    path = file_holding("\uFEFF{\"new-checkout\": true}")
    client = offline_client(file: path)

    expect { client.init }.to raise_error(
      ConfigDirector::ConfigDirectorInitializationError,
      /\AThe offline values file '#{Regexp.escape(path)}' is not valid JSON: ./
    )
  end

  it "logs nothing when init raises the initialization error" do
    client = offline_client(file: File.join(folder, "missing.json"))

    expect { client.init }.to raise_error(ConfigDirector::ConfigDirectorInitializationError)
    expect(logger.messages_at(:warn) + logger.messages_at(:error)).to be_empty
  end

  it "reads the file again at a later init, naming every key it carries and the keys it no longer carries" do
    path = file_holding('{"max-items": 20, "new-checkout": true}')
    client = offline_client(file: path, timeout: 0.2)
    client.init
    deliveries = []
    client.on(:configs_updated) { |update| deliveries << update }
    client.watch("new-checkout", false) { |value| deliveries << [:watch, value] }
    client.on(:client_ready) { deliveries << :client_ready }
    File.write(path, '{"max-items": 30}')

    client.init

    expect(deliveries).to eq(
      [ConfigDirector::ConfigsUpdatedEvent.new(keys: ["max-items"], removed_keys: ["new-checkout"]), [:watch, false]]
    )
    expect(client.get_value("max-items", 0)).to eq(30)
  end

  it "keeps serving its values and stays ready when a later init cannot read the file" do
    path = file_holding('{"max-items": 20}')
    client = offline_client(file: path, timeout: 0.2)
    client.init
    File.delete(path)

    expect { client.init }.to raise_error(ConfigDirector::ConfigDirectorInitializationError)
    expect(client.ready?).to be(true)
    expect(client.get_value("max-items", 0)).to eq(20)
  end

  it "becomes ready at a later init once the file can be read" do
    path = File.join(folder, "flags.json")
    client = offline_client(file: path, timeout: 0.2)
    client_ready_calls = []
    client.on(:client_ready) { client_ready_calls << :client_ready }
    expect { client.init }.to raise_error(ConfigDirector::ConfigDirectorInitializationError)
    File.write(path, '{"max-items": 20}')

    client.init

    expect(client.ready?).to be(true)
    expect(client.get_value("max-items", 0)).to eq(20)
    expect(client_ready_calls).to eq([:client_ready])
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "delivers its values again at a later init, without calling client_ready again" do
    client = offline_client(values: { "new-checkout" => true, "max-items" => 20 }, timeout: 0.2)
    client.init
    deliveries = []
    client.on(:configs_updated) { |update| deliveries << update }
    client.watch("max-items", 0) { |value| deliveries << [:watch, value] }
    client.on(:client_ready) { deliveries << :client_ready }

    client.init

    expect(deliveries).to eq(
      [ConfigDirector::ConfigsUpdatedEvent.new(keys: %w[new-checkout max-items], removed_keys: []), [:watch, 20]]
    )
  end

  it "calls configs_updated with no keys at a later init when it has no values" do
    client = offline_client(timeout: 0.2)
    client.init
    updates = updates_received_by(client)

    client.init

    expect(updates.size).to eq(1)
    expect(updates.pop).to eq(ConfigDirector::ConfigsUpdatedEvent.new(keys: [], removed_keys: []))
  end

  it "returns at once from an init that a handler calls during init, delivering nothing again" do
    client = offline_client(values: { "max-items" => 20 })
    updates = []
    client.on(:configs_updated) do |update|
      updates << update
      client.init
    end

    client.init

    expect(updates).to eq([ConfigDirector::ConfigsUpdatedEvent.new(keys: ["max-items"], removed_keys: [])])
  end

  it "returns the in-code default value of a key the values leave out, as a missing config" do
    client = offline_client(values: { "new-checkout" => true })
    client.init

    evaluation = client.evaluate("max-items", 10)

    expect(evaluation.value).to eq(10)
    expect(evaluation.reason).to eq("config-state-missing")
  end

  it "calls configs_updated with every key, then the watches, then client_ready once during init" do
    client = offline_client(values: { "new-checkout" => true, "max-items" => 20 })
    deliveries = []
    client.on(:configs_updated) { |update| deliveries << update }
    client.watch("max-items", 0) { |value| deliveries << [:watch, value] }
    client.on(:client_ready) { deliveries << :client_ready }

    client.init

    expect(deliveries).to eq(
      [
        ConfigDirector::ConfigsUpdatedEvent.new(keys: %w[new-checkout max-items], removed_keys: []),
        [:watch, 20],
        :client_ready
      ]
    )
  end

  it "serves its values after an init with a timeout of 0, and logs no warning" do
    client = offline_client(values: { "new-checkout" => true }, timeout: 0)

    client.init

    expect(client.get_value("new-checkout", false)).to be(true)
    expect(logger.messages_at(:warn)).to be_empty
  end

  it "sends no telemetry for its reads, not even when it is closed" do
    client = offline_client(values: { "new-checkout" => true }, url: sdk_server.url)
    client.init
    client.get_value("new-checkout", false, ConfigDirector::Context.new(id: "user-123"))

    client.close

    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::TELEMETRY_PATH, within: 0.2)).to be(false)
  end

  it "logs an error for a context with an invalid kind on every read" do
    client = offline_client(values: { "new-checkout" => true })
    client.init

    3.times { client.get_value("new-checkout", false, ConfigDirector::Context.new(kind: "Device")) }

    expect(logger.messages_at(:error).length).to eq(3)
    expect(logger.messages_at(:error)).to all(include("Device"))
  end

  it "asks the SDK server for nothing and starts no thread" do
    sdk_server_url = sdk_server.url
    threads_before_the_client = Thread.list
    client = offline_client(values: { "new-checkout" => true }, url: sdk_server_url)

    client.init

    expect(Thread.list).to eq(threads_before_the_client)
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::STREAM_PATH, within: 0.2)).to be(false)
    expect(sdk_server.receives_a_request_to?(ScriptedSdkServer::POLLING_PATH, within: 0)).to be(false)
  end
end
