# Rails sample

A minimal [Rails](https://rubyonrails.org) API application using the ConfigDirector Ruby server SDK, served by
[Puma](https://puma.io) in cluster mode. It mirrors the Flask sample in the Python SDK and the Gin sample in the Go
SDKs: a single `/configs` route that evaluates a handful of configs and returns them as JSON.

It is the smallest Rails application that serves JSON: API only, with no database, mailer, jobs or assets. It
depends on the two Rails frameworks it uses, `railties` and `actionpack`, rather than on `rails`.

## Running it

You need Bundler and Ruby 3.3.13, 3.4.12, 4.0.9 or a later release on the same line.

```bash
cd samples/configdirector-server-sdk/rails
bundle install
cp .env.example .env      # then set your server SDK key; the sample also runs without a real key
bundle exec puma
```

Bundler installs the sample's gems into its own `vendor/bundle`, as [`.bundle/config`](.bundle/config) says, and
takes the SDK from this working tree until the SDK's first release.

Puma reads [`config/puma.rb`](config/puma.rb): 2 workers on port 3800. With more than one worker, Puma 7 and later
load the application once, in the master process, and then fork the workers from it.

Then:

```bash
curl 'http://localhost:3800/configs?id=user-123&plan=pro'
```

```json
{
  "temporary-feature-flag": true,
  "permanent-kill-switch": true,
  "integer-config": 42,
  "day-of-the-week-config": "Tuesday",
  "json-value-config": {"greeting": "hello", "sizes": [1, 2]}
}
```

Those are the values of an environment that has the five configs, with a targeting rule that serves `Tuesday` to
the `pro` plan. Without a real server SDK key, or for a config the environment does not have, the sample answers
with the in-code default value instead: see [Running without a server SDK key](#running-without-a-server-sdk-key).

Query parameters double as the context the configs are evaluated for: `id`, `kind`, `name` and `anonymous` map to
the matching `Context` fields, and anything else becomes a trait:

```
/configs?id=user-123&name=Ada&plan=pro&region=eu
```

Any other route, `POST /configs` and `/configs.json` included, answers `404` with a hint to `GET /configs`, apart
from the pages Rails adds under `/rails/info` in the development environment. Stop the server with Ctrl-C.

Run the tests with `bundle exec rspec`.

## One client per process

This is the most important thing the sample shows.
[`lib/config_director_client_per_process.rb`](lib/config_director_client_per_process.rb) creates the client the
first time a process reads a config, calls `init`, and returns the same client to every later request in that
process:

```ruby
def self.client
  @lock.synchronize { @client ||= created_and_initialized_client }
end
```

[`ConfigsController`](app/controllers/configs_controller.rb) reads all five configs through it:

```ruby
client = ConfigDirectorClientPerProcess.client
```

Each Ruby process holds its own client, and each client holds its own connection to ConfigDirector. A client is
safe to share between threads, so every Puma thread in a worker reads through that worker's client, and the lock
makes sure two first requests arriving together still end up with one client. Never create a client inside a
request: each one waits in `init` for its first values, opens a connection of its own, and takes its handlers and
watches with it when it is dropped.

Nothing creates the client while the application loads, in an initializer or in `config/application.rb`. A client
created while a Rails application boots would also connect in the Puma master, which serves no request, in
`bin/rails console` and in every task that loads the application, and in an application that requires the key,
creating it would raise during `assets:precompile` in an image build that has no server SDK key. Created on first
use, a client exists only in a process that reads a config, so only such a process connects, and the first
request in each worker waits for the first values, up to `CONFIGDIRECTOR_TIMEOUT` seconds. With the two workers
above, the log shows one line for each worker, after its first request, and none for the master:

```
Created the ConfigDirector client of process 13548. Ready: true
Created the ConfigDirector client of process 13547. Ready: true
```

A client initialized before Puma forks its workers, in an initializer for instance, is copied into each worker and
starts its own connection there by itself, so its values keep changing in every worker. The sample does not depend
on that, because it creates no client before the fork.

`config/application.rb` loads `lib/` with `autoload_lib_once`, so Rails does not reload the module when code
changes in development. A reloaded module would forget its client and create a second one.

### Paying the wait at startup

To have each worker wait for its first values before it serves a request, call the same method from Puma's
`before_worker_boot` hook in `config/puma.rb`:

```ruby
before_worker_boot do
  ConfigDirectorClientPerProcess.client
end
```

The hook runs in each worker after the fork, so each worker still creates its own client and the master creates
none.

## What else it demonstrates

**Initialization is explicit and non-fatal.** `init` waits for the first values, up to `CONFIGDIRECTOR_TIMEOUT`
seconds. When none arrive in time it logs a warning and returns, and every read returns its in-code default value
until values arrive. When ConfigDirector refuses the server SDK key it logs an error and returns at once. The sample
logs whether the client is ready once it has created it. Creating the client makes no network call.

**In-code default values are the fallback.** Every `get_value` call passes the value to serve when ConfigDirector
cannot provide one, so it should be the safe choice. Its class also decides how the config value is read: `true` or
`false`, a String, an Integer, a Float, or a Hash for a JSON object.

**The context is per request; the client is not.** `context_from_query` in
[`ConfigsController`](app/controllers/configs_controller.rb) maps query parameters onto a `Context`. A real
application would build it from the signed-in user.

**Logging goes through `Rails.logger`.** The sample passes `Rails.logger` as `logger:`, so the SDK's lines land in
the application's log, which the development environment writes to standard output. `CONFIGDIRECTOR_LOG_LEVEL` sets
the level of `Rails.logger`, `info` unless it is set. Set it to `debug` to see each config the SDK evaluates:

```
[ConfigDirectorClient] Evaluated "day-of-the-week-config" to "Tuesday" (found-match)
```

**Settings come from the environment.** The sample reads the key, connection mode, timeout and base URL from the
`CONFIGDIRECTOR_*` variables in [`.env.example`](.env.example), and passes only the options the environment names,
so every other option keeps the SDK's default. A variable set to an empty value counts as not set. In the
development environment, which `bundle exec puma` runs, the [dotenv](https://github.com/bkeepers/dotenv) gem adds
the variables in a `.env` file, without overriding a variable already set in the environment. A mode or base URL the
SDK refuses, or a timeout that is not a number, makes every request to `/configs` answer `500`, and the log shows
why.

**Shutdown is clean.** When a process that created a client exits, an `at_exit` handler closes the client, which
closes its connection and reports what the process evaluated since its last report. Puma's workers run it when they
stop gracefully, after Ctrl-C or `SIGTERM`.

The SDK also supports watching configs and subscribing to the client's events; see `watch` and `on` in
[`ConfigDirectorClient`](../../../configdirector-server-sdk/lib/configdirector/config_director_client.rb).

## Testing

The suite calls the application in process, so no web server runs. The request specs in
[`spec/requests/`](spec/requests/) send requests through Rails' integration session, and through Rack's
`MockRequest` for two first requests that arrive together on two threads.
[`spec/processes_spec.rb`](spec/processes_spec.rb) runs `bin/rails runner` to check what a process does when it
loads the application without a key and when it exits.

The tests never connect to ConfigDirector. They read through the SDK's test client: a real client whose values the
test sets, with no network connection and no thread. Before each example,
[`spec/support/test_client_in_place_of_the_application_client.rb`](spec/support/test_client_in_place_of_the_application_client.rb)
creates a test client that serves the five configs of
[`spec/support/five_standard_configs.rb`](spec/support/five_standard_configs.rb), and makes `ConfigDirector.create_client`
return its client:

```ruby
let(:test_client) { ConfigDirector::Testing.create_test_client(FiveStandardConfigs::VALUES, logger: Rails.logger) }

before { allow(ConfigDirector).to receive(:create_client).and_return(test_client.client) }
```

The first request of an example then goes through `ConfigDirectorClientPerProcess` as it does in production: it
creates the client, which is the test client's, and calls `init`, which serves the five values at once. A test changes
a value between two requests with `set_value`, and the next request reads the new value:

```ruby
get "/configs"
test_client.set_value("integer-config", 7)

get "/configs"

expect(response.parsed_body["integer-config"]).to eq(7)
```

The example in [`spec/processes_spec.rb`](spec/processes_spec.rb) that creates a client runs `bin/rails runner` in
offline mode, so that process does not connect to ConfigDirector either.

To see the context each config was evaluated for, a test registers a `config_evaluated` handler on the process's
client before it sends the request:

```ruby
ConfigDirectorClientPerProcess.client.on(:config_evaluated) do |event|
  evaluated_contexts << event.evaluation.context
end

get "/configs?id=user-123&kind=device&name=Ada&anonymous=true&plan=pro&region=eu"
```

After each example, [`spec/rails_helper.rb`](spec/rails_helper.rb) closes the process's client and clears it from
the module, so the next example starts without one.

## Running without a server SDK key

Without `CONFIGDIRECTOR_SERVER_KEY` the sample creates its client with `fake-sample-key`. ConfigDirector refuses
that key, so the client logs an error and stays not ready, and every config falls back to the in-code default value
this app passes in:

```json
{
  "temporary-feature-flag": true,
  "permanent-kill-switch": false,
  "integer-config": 10,
  "day-of-the-week-config": "Friday",
  "json-value-config": {}
}
```

That is the path a production app takes with a wrong key or no network, so it is worth seeing: the app keeps
serving, on the in-code default values you chose.
