# Sinatra sample

A minimal [Sinatra](https://sinatrarb.com) application reading ConfigDirector configs through
[OpenFeature](https://openfeature.dev), using the ConfigDirector OpenFeature Ruby server provider, served by
[Puma](https://puma.io). It is the OpenFeature counterpart of the [server SDK's Rails
sample](../../configdirector-server-sdk/rails/): the same `/configs` route, evaluating the same five configs for an
evaluation context taken from the query string, plus `/configs/<key>` with the evaluation details of one boolean
flag.

## Running it

You need Bundler and Ruby 3.4.12, 4.0.9 or a later release on the same line. The provider does not support Ruby
3.3.

```bash
cd samples/configdirector-openfeature-server-provider/sinatra
bundle install
cp .env.example .env      # then set your server SDK key; the sample also runs without a real key
bundle exec puma
```

Bundler installs the sample's gems, the released provider and SDK among them, into its own `vendor/bundle`, as
[`.bundle/config`](.bundle/config) says. Puma reads [`config/puma.rb`](config/puma.rb), which sets port 3820, and
loads the application from [`config.ru`](config.ru), which also reads `.env`.

Then:

```bash
curl 'http://localhost:3820/configs?id=user-123&plan=pro'
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

Query parameters double as the evaluation context: `id` becomes the targeting key, `name` and `anonymous` become the
attributes of the same name, and anything else, `kind` included, becomes a trait in the `traits` attribute:

```
/configs?id=user-123&name=Ada&plan=pro&region=eu
```

`/configs/<key>` returns the evaluation details of one boolean flag, which is the quickest way to see why a value
was served. Without a real server SDK key it answers:

```bash
curl 'http://localhost:3820/configs/temporary-feature-flag?id=user-123'
```

```json
{
  "value": false,
  "variant": null,
  "reason": "ERROR",
  "error_code": "PROVIDER_NOT_READY",
  "error_message": "ConfigDirector has not delivered config state yet."
}
```

Any other route, `POST /configs` included, answers `404` with a hint to `GET /configs`. Stop the server with
Ctrl-C.

Run the tests with `bundle exec rspec`.

## One provider per process

This is the most important thing the sample shows.
[`lib/open_feature_client_per_process.rb`](lib/open_feature_client_per_process.rb) registers the ConfigDirector
provider with OpenFeature the first time a process asks for its OpenFeature client, and returns the same client to
every later request in that process:

```ruby
def self.client
  @lock.synchronize { @client ||= client_after_registering_the_provider }
end
```

The routes in [`app.rb`](app.rb) read every config through it:

```ruby
client = OpenFeatureClientPerProcess.client
```

Each Ruby process holds its own provider, and each provider holds its own connection to ConfigDirector. Every
Puma thread of the process reads through the same client, and the lock makes sure two first requests arriving
together still register one provider. Never register a provider for each request: each new provider opens a
connection of its own and waits for its first config before it serves one.

Nothing registers the provider while the application loads, in `app.rb` or in `config.ru`. Registered on first use,
a provider exists only in a process that reads a config, so a console, a task or an image build that loads the
application without a server SDK key never connects, and the tests can put another provider in its place. The
first request of a process waits for config, up to `CONFIGDIRECTOR_TIMEOUT` seconds, and the log shows one line
for the process:

```
Registered the ConfigDirector provider of process 84204. Status: READY
```

With more than one worker in `config/puma.rb`, Puma loads the application in its master process and forks the
workers from it, so each worker registers its own provider on its first request and holds its own connection to
ConfigDirector, while the master holds none. A provider registered in the master, before the fork, would still work
in each worker, because its ConfigDirector client restarts by itself in each forked process, but the master would
then hold a connection it never uses.

## What else it demonstrates

**Initialization is explicit and non-fatal.** `OpenFeature::SDK.set_provider_and_wait` waits for config, up to
`CONFIGDIRECTOR_TIMEOUT` seconds. When none arrives in time, or ConfigDirector refuses the server SDK key, it raises
`OpenFeature::SDK::ProviderInitializationError`. The sample logs the error as a warning and keeps serving:

```ruby
def self.register(provider, logger)
  OpenFeature::SDK.set_provider_and_wait(provider)
rescue OpenFeature::SDK::ProviderInitializationError => e
  logger.warn(e.message)
end
```

OpenFeature then reports the `ERROR` status, and every read returns its in-code default value with the error code
`PROVIDER_NOT_READY`. After a timeout the provider keeps connecting, and OpenFeature reports `READY` once config
arrives.

**In-code default values are the fallback.** Every read passes the value to serve when ConfigDirector cannot
provide one, so it should be the safe choice. The method decides the type the config value is read as:
`fetch_boolean_value`, `fetch_integer_value`, `fetch_string_value`, and `fetch_object_value` for a JSON config.

**Details explain a value.** `/configs/<key>` reads one flag with `fetch_boolean_details` and returns its value,
variant, reason, error code and error message. The [provider's
README](../../../configdirector-openfeature-server-provider/README.md#evaluation-details) says what each reason and
error code means.

**The evaluation context is per request; the provider is not.** `evaluation_context_from_query` in
[`app.rb`](app.rb) maps query parameters onto an OpenFeature `EvaluationContext`. A real application would build it
from the signed-in user.

**Settings come from the environment.** The sample reads the server SDK key, connection mode, timeout, base URL and
log level from the `CONFIGDIRECTOR_*` variables in [`.env.example`](.env.example), the same ones the server SDK's
sample reads, and passes only the options the environment names, so every other option keeps the SDK's default.

**Logging goes through one logger.** The sample writes to standard output with a Ruby `Logger` at the level
`CONFIGDIRECTOR_LOG_LEVEL` names, `info` unless it is set, and passes it to the provider as `logger:`, so the SDK's
lines land in the same log. Set it to `debug` to see each config the SDK evaluates:

```
[ConfigDirectorClient] Evaluated "day-of-the-week-config" to "Tuesday" (found-match)
```

**Shutdown is clean.** When the process exits, the sample shuts OpenFeature down, which closes the provider's
connection and sends what the process evaluated since its last report. Puma exits that way after Ctrl-C or
`SIGTERM`.

## Testing

The suite calls the application in process with [Rack::Test](https://github.com/rack/rack-test), so no web server
runs.

The tests never connect to ConfigDirector. They read through the in-memory provider the OpenFeature Ruby SDK ships,
`OpenFeature::SDK::Provider::InMemoryProvider`, the way an application that reads flags through OpenFeature tests
itself. Before each example,
[`spec/support/in_memory_provider_in_place_of_the_configdirector_provider.rb`](spec/support/in_memory_provider_in_place_of_the_configdirector_provider.rb)
creates an in-memory provider that serves the five configs of
[`spec/support/five_standard_configs.rb`](spec/support/five_standard_configs.rb), and makes
`ConfigDirector::OpenFeature::ConfigDirectorProvider.new` return it:

```ruby
let(:in_memory_provider) { OpenFeature::SDK::Provider::InMemoryProvider.new(FiveStandardConfigs::VALUES.dup) }

before do
  allow(ConfigDirector::OpenFeature::ConfigDirectorProvider).to receive(:new).and_return(in_memory_provider)
end
```

The first request of an example then goes through `OpenFeatureClientPerProcess` as it does in production: it
registers the provider, which is the in-memory one, with `set_provider_and_wait`. A test changes a value between two
requests with `add_flag`, and the next request reads the new value:

```ruby
get "/configs"
in_memory_provider.add_flag(flag_key: "integer-config", value: 7)

get "/configs"

expect(JSON.parse(last_response.body)["integer-config"]).to eq(7)
```

A value that responds to `call` is called with the evaluation context of each read, which is how a test sees the
context the provider received.

After each example, [`spec/spec_helper.rb`](spec/spec_helper.rb) shuts OpenFeature down and clears the client from
the module, so the next example registers its own provider. The examples capture standard output, where the sample
logs, so a test can read the log and the suite's output stays clean.

[`spec/processes_spec.rb`](spec/processes_spec.rb) starts Ruby processes that load the application, to check that
loading creates no provider and that the first request connects. The first request connects to a local socket the
test listens on in place of ConfigDirector, and the process that checks the shutdown at exit runs in offline mode,
so neither connects to ConfigDirector.

## Running without a server SDK key

Without `CONFIGDIRECTOR_SERVER_KEY` the sample creates its provider with `fake-sample-key`. ConfigDirector refuses
that key, so the SDK logs an error, the sample logs the initialization error as a warning, and every config falls
back to the in-code default value this application passes in:

```json
{
  "temporary-feature-flag": true,
  "permanent-kill-switch": false,
  "integer-config": 10,
  "day-of-the-week-config": "Friday",
  "json-value-config": {}
}
```

That is the path a production application takes with a wrong key or no network, so it is worth seeing: the
application keeps serving, on the in-code default values you chose.
