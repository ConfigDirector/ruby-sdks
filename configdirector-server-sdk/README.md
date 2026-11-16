# ConfigDirector Ruby SDK

[![CI][ci-badge]][ci] [![Gem Version][gem-badge]][gem]

Ruby server SDK for [ConfigDirector](https://www.configdirector.com), remote config and feature flags with JSON Schema validation and safe renames of live flags. Start free, no card required.

The SDK requires Ruby 3.3 or later. It is in development and has not been released yet.

## Install

```bash
bundle add configdirector-server-sdk
```

## Retrieve a value

```ruby
require "configdirector"

# The server SDK key is a secret. Do not commit it to your source code.
client = ConfigDirector.create_client(ENV.fetch("CONFIGDIRECTOR_SERVER_KEY"))
client.init

new_checkout = client.get_value("new-checkout", false)
```

Full details are in the [official documentation](https://docs.configdirector.com/sdks/server/ruby).

## Servers that fork

Each Ruby process holds its own connection to ConfigDirector, on a thread of the SDK, so an application on 2 hosts with
4 Puma workers each holds 8 connections. Puma in cluster mode, Passenger's smart spawning and Unicorn with `preload_app
true` load the application once and then fork their workers from that process. A client that was initialized before the
fork restarts by itself in each worker: it serves the values it had at the fork at once, opens its own connection and
keeps calling its handlers and watches, with nothing for your application to call.

Create the client the first time a process uses it rather than while the application boots, as the [Rails
sample](https://github.com/ConfigDirector/ruby-sdks/tree/main/samples/configdirector-server-sdk/rails) does. Then only a
process that reads a config connects: the Puma master and an image build that has no server SDK key never do, and
neither does a `bin/rails console` session or a Rake task until it reads one. The first request in each worker waits for
the first values, up to the connection timeout. The [documentation](https://docs.configdirector.com/sdks/server/ruby)
also says what an application that forks for each background job should do.

## Test your code

`configdirector/testing` creates a **test client**: the SDK's real client over an in-memory connection that your test
controls. It opens no network connection, starts no thread and sends nothing. Set values, change them in the middle
of a test so watches and `configs_updated` handlers run, and hold or fail initialization to test what your code does
before values arrive. It ships in the gem, so there is nothing else to install.

```ruby
require "configdirector/testing"

test_client = ConfigDirector::Testing.create_test_client({ "new-checkout" => true })
service = CheckoutService.new(test_client.client)
test_client.client.init

expect(service.new_checkout_enabled?("user-123")).to be(true)

test_client.set_value("new-checkout", false)
expect(service.new_checkout_enabled?("user-123")).to be(false)

test_client.client.close
```

`test_client.client` is a `ConfigDirector::ConfigDirectorClient`, so it goes anywhere your code takes one. It starts
not ready, like a production client, because the code under test usually owns the call to `init`. Unless
initialization is held or set to fail, `init` serves the stored values at once. The test client has no `close` of its
own: close its client when the test ends.

### Values

`create_test_client`, `set_value` and `replace_values` take Ruby values, and the config type follows from the class of
each value: `true` or `false` is a boolean config, an Integer an integer config, a Float a float config, a String a
string config, and a Hash or an Array a JSON config, which can hold `nil`. A key is a String or a Symbol, and a Symbol
is read as its name. A String is always a string config, so JSON text meant as a JSON config is given as
`JSON.parse(text)`. Every context receives the same value, as a match with no value ID and no variation, so a test that
needs different values for different contexts is written as one test per value. A value the SDK cannot serve, such as
`nil`, a Symbol or a Float that is not finite, raises `ConfigDirector::ConfigDirectorValidationError`, and so does a
blank key or a key of another class. Nothing changes then.

Reads behave as they do in production: `set_value("new-checkout", true)` read with a String in-code default value
returns that in-code default value with the reason `type-mismatch`, `set_value("max-items", 2.5)` read with an Integer
returns it with `invalid-number`, and `set_value("banner-text", "")` returns it with `value-missing`. The reason is on
the evaluation that `evaluate` returns and that `config_evaluated` handlers receive. A Hash keeps its order.

### Controls

| Control | What it does |
| --- | --- |
| `set_value(key, value)` | Stores the value and, while the client is connected, delivers an update that carries only `key`. Reads, the watches of `key` and the `configs_updated` handlers see it before the call returns. |
| `remove_value(key)` | Removes the value and delivers a full update without it. Reads return the in-code default value with the reason `config-state-missing`, the watches of `key` receive that in-code default value, and `configs_updated` handlers find `key` in `removed_keys`. |
| `replace_values(values)` | Replaces every stored value, cancels a hold or a failure that no `init` has used yet, and delivers a full update. Use it to reset a test client shared between tests. |
| `hold_initialization` | The next `init` waits until another thread calls `complete_initialization` or `fail_initialization`, or until the timeout. `init` blocks, so a test calls it on another thread. |
| `complete_initialization` | Delivers the stored values to the held `init`, on the calling thread, so the client is ready when the call returns. The held `init` returns once the handlers and watches of those values have run. Called before `init` while a hold is set, it cancels the hold. |
| `fail_initialization` | Fails the held `init` the way a refused server SDK key does: the client is not ready, an error is logged and the `connection_error` handlers receive a `ConfigDirectorConnectionError` with the status 401, on the calling thread, and then the held `init` returns. Called while no `init` is held, it makes the next `init` fail, which then returns at once. |

The `init` after a failed one serves the stored values, the ones set in the meantime included. A change made while the
client is not connected, before `init` or after a held or failed one, is stored and reaches the client with the next
`init` that serves the values.

### Tracked events

`test_client.tracked_events` holds every event the code under test tracked, in call order, as
`ConfigDirector::Testing::TrackedEvent` (`name`, `context`, `value`, `details`), so a test can assert on them:

```ruby
require "configdirector/testing"

test_client = ConfigDirector::Testing.create_test_client
test_client.client.track("checkout-completed", ConfigDirector::Context.new(id: "user-123"), value: 49.9)

expect(test_client.tracked_events).to eq(
  [
    ConfigDirector::Testing::TrackedEvent.new(
      name: "checkout-completed", context: ConfigDirector::Context.new(id: "user-123"), value: 49.9
    )
  ]
)
```

The record follows the rules of a real report: an event whose name does not have 1 to 150 characters is not
recorded, and a value or details the SDK would leave out are missing from the record, with a warning logged each time.
The details are recorded as the SDK sends them, so their keys are Strings and a Time is its ISO 8601 text in UTC. The
limit of 1,000 events per report does not apply, and nothing is recorded once the client is closed. It is the same
Array on every call, so `test_client.tracked_events.clear` empties it.

### Options

`create_test_client(values, timeout: nil, logger: nil)` takes `timeout`, in seconds, which is how long a held `init`
waits, 3 seconds unless given, as for a production client; and `logger`, any object with the methods of Ruby's
`Logger`, as `ConfigDirector.create_client` takes it. Without a logger the SDK writes warnings and errors to standard
error.

### Module-level clients

An application that creates and initializes its client while it loads, in a Rails initializer for example, runs the
real client before any test can step in: the client opens a connection and starts a thread. Create the client the
first time a process uses it instead, as the
[Rails sample](https://github.com/ConfigDirector/ruby-sdks/tree/main/samples/configdirector-server-sdk/rails) does:

```ruby
module ConfigDirectorClientPerProcess
  @lock = Mutex.new
  @client = nil

  def self.client
    @lock.synchronize do
      @client ||= ConfigDirector.create_client(ENV.fetch("CONFIGDIRECTOR_SERVER_KEY")).tap(&:init)
    end
  end
end
```

The lock matters on a threaded server such as Puma: without it, two first requests arriving together each create and
initialize a client.

In your tests, make `ConfigDirector.create_client` return the test client's client before the application first uses
one, and forget the client after each example, so the next example creates its own:

```ruby
RSpec.shared_context "with a test client" do
  let(:test_client) { ConfigDirector::Testing.create_test_client({ "new-checkout" => true }) }

  before { allow(ConfigDirector).to receive(:create_client).and_return(test_client.client) }

  after do
    test_client.client.close
    ConfigDirectorClientPerProcess.instance_variable_set(:@client, nil)
  end
end
```

### What to expect

- The first values are delivered while `init` runs, so watches registered before `init` run before it returns, and the
  `configs_updated` handlers run before the `client_ready` handlers.
- Watches and handlers run on the thread that calls `set_value`, `remove_value`, `replace_values`,
  `complete_initialization` or `init`, never on a thread of the SDK. A change made from inside a handler or a watch is
  delivered right after the one being handled.
- A held `init` that reaches the timeout logs the SDK's timeout warning, and a client that was not ready stays not ready
  until the next `init`. A client that was ready keeps serving its values through a later held or failed `init`, and
  completing such an `init` calls no `client_ready` handler.
- Each failed `init` calls the `connection_error` handlers, where a client connected to ConfigDirector calls them at most
  once.
- A `close` or an `init` called while an `init` is held, from another thread or from a handler that
  `complete_initialization` or `fail_initialization` runs, returns once the held `init` returns.
- Watches run for every update that carries their key, whether or not the value changed, as in production.
  `remove_value` and `replace_values` deliver a full update, so they also run the watches of every key left.
- A `StandardError` a watch or a handler raises is logged and does not reach the caller, as in production. An exception
  that is not a `StandardError`, such as a failed RSpec expectation, reaches the call that delivered the change.
- After `close`, `ready?` is false, every read returns its in-code default value, `get_all_configs` returns an empty
  Hash, `init` raises `ConfigDirectorValidationError`, every handler and watch has been removed, and the closed client
  takes none of the values the test client's controls store.
- The SDK keeps no reference to a test client's client, so one that is never closed can be garbage collected. In a
  forked process it keeps serving its values, with nothing to restart.

## Documentation

Refer to the [official documentation for the Ruby SDK](https://docs.configdirector.com/sdks/server/ruby).

There is also [a quickstart guide for ConfigDirector and any of our SDKs](https://docs.configdirector.com/getting-started/quickstart).

## Sample apps

[`samples/configdirector-server-sdk/`](https://github.com/ConfigDirector/ruby-sdks/tree/main/samples/configdirector-server-sdk)
holds small, runnable applications built on this SDK. Start with
[`rails`](https://github.com/ConfigDirector/ruby-sdks/tree/main/samples/configdirector-server-sdk/rails), a Rails
application served by Puma in cluster mode:

```bash
cd samples/configdirector-server-sdk/rails
bundle install
bundle exec puma
```

## OpenFeature

To read flags through the [OpenFeature](https://openfeature.dev) API, use the [`configdirector-openfeature-server-provider`](https://github.com/ConfigDirector/ruby-sdks/tree/main/configdirector-openfeature-server-provider) gem, which is built on this SDK.

## Getting Help

- [Ask a question in Discussions](https://github.com/orgs/ConfigDirector/discussions)
- [Contact support](https://www.configdirector.com/support)

[//]: # "links"
[ci-badge]: https://github.com/ConfigDirector/ruby-sdks/actions/workflows/ci.yml/badge.svg
[ci]: https://github.com/ConfigDirector/ruby-sdks/actions/workflows/ci.yml
[gem-badge]: https://img.shields.io/gem/v/configdirector-server-sdk
[gem]: https://rubygems.org/gems/configdirector-server-sdk
