# ConfigDirector OpenFeature Ruby Server Provider

[![CI][ci-badge]][ci] [![Gem Version][gem-badge]][gem]

[OpenFeature](https://openfeature.dev) Ruby server provider for [ConfigDirector](https://www.configdirector.com), remote config and feature flags with JSON Schema validation and safe renames of live flags. It is built on the [ConfigDirector Ruby server SDK](https://github.com/ConfigDirector/ruby-sdks/tree/main/configdirector-server-sdk).

The provider requires Ruby 3.4 or later.

## Install

```bash
bundle add configdirector-openfeature-server-provider
```

The OpenFeature Ruby SDK (`openfeature-sdk`) and the ConfigDirector Ruby server SDK come with it as dependencies.

## Retrieve a value

```ruby
require "configdirector/openfeature"

# The server SDK key is a secret. Do not commit it to your source code.
OpenFeature::SDK.set_provider_and_wait(
  ConfigDirector::OpenFeature::ConfigDirectorProvider.new(ENV.fetch("CONFIGDIRECTOR_SERVER_KEY"))
)
client = OpenFeature::SDK.build_client

new_checkout = client.fetch_boolean_value(flag_key: "new-checkout", default_value: false)
```

`set_provider_and_wait` waits up to the connection timeout, 3 seconds by default, for config to arrive. If none arrives in time, or ConfigDirector rejects the server SDK key, it raises `OpenFeature::SDK::ProviderInitializationError` with the error code `PROVIDER_NOT_READY`, and OpenFeature reports the `ERROR` status. Reads then return their in-code default values with `PROVIDER_NOT_READY`. After a timeout the provider keeps connecting, and OpenFeature reports `READY` once config arrives.

To start without waiting for ConfigDirector, call `OpenFeature::SDK.set_provider` instead, which initializes the provider in the background, or rescue the error:

```ruby
begin
  OpenFeature::SDK.set_provider_and_wait(
    ConfigDirector::OpenFeature::ConfigDirectorProvider.new(ENV.fetch("CONFIGDIRECTOR_SERVER_KEY"))
  )
rescue OpenFeature::SDK::ProviderInitializationError => e
  Rails.logger.warn("Starting on in-code default values until ConfigDirector sends config: #{e.message}")
end
```

The provider takes the same `metadata`, `connection`, `logger`, `log_level` and `telemetry` options as the server SDK's `ConfigDirector.create_client`.

A provider that was registered before the process forked, as in a Puma worker, keeps working in the forked process: its client restarts by itself there, as the [server SDK's README](https://github.com/ConfigDirector/ruby-sdks/tree/main/configdirector-server-sdk#servers-that-fork) describes.

## Evaluation context

The OpenFeature evaluation context maps onto the ConfigDirector context used by targeting rules:

| OpenFeature | ConfigDirector |
|---|---|
| `targeting_key`, or failing that an `id` attribute | `id` |
| `kind` attribute | `kind` |
| `name` attribute | `name` |
| `traits` attribute, a Hash | `traits` |
| `anonymous` attribute, `true` | `anonymous` |

```ruby
context = OpenFeature::SDK::EvaluationContext.new(targeting_key: "user-123", name: "Ada", traits: { "plan" => "pro" })
new_checkout = client.fetch_boolean_value(flag_key: "new-checkout", default_value: false, evaluation_context: context)

device = OpenFeature::SDK::EvaluationContext.new(targeting_key: "kiosk-7", kind: "device")
new_checkout = client.fetch_boolean_value(flag_key: "new-checkout", default_value: false, evaluation_context: device)
```

An id or a name given as a Symbol, `true` or `false`, an Integer, a Float or a date is read as text, and any other id or name is left out. A date, given as a `Time`, a `DateTime` or a `Date`, is written as UTC text such as `2026-11-17T10:00:00.000Z`, or as `2026-11-17` for a `Date`, inside the traits too, so date conditions can compare it.

Without a `kind` attribute the context is a `user`, and a `kind` inside `traits` is an ordinary trait. A kind has 1 to 64 characters, using only lowercase letters, digits, `-` and `_`. When the kind is invalid, including any kind that is not text, the whole context is ignored: the read still resolves, to the value for no context, and the SDK logs an error.

A context with neither a targeting key nor an `id` attribute skips percentage rollouts: the targeting rules after the rollout are tried, and the flag resolves to the default targeting rule value when none applies. Give an anonymous context a stable targeting key, such as a session ID, to keep it in a rollout.

## Evaluation details

| Outcome | `reason` | `error_code` |
|---|---|---|
| A value was served | `TARGETING_MATCH`, with the variation's name as the `variant` when it has one, otherwise the value's ID | |
| A percentage rollout was skipped because the context has no targeting key or `id` | `DEFAULT`, with the `variant` of the default targeting rule value | |
| The config has no value | `DEFAULT` | |
| No config has that key | `ERROR` | `FLAG_NOT_FOUND` |
| The value cannot be read as the requested type | `ERROR` | `TYPE_MISMATCH` |
| No config has arrived yet | `ERROR` | `PROVIDER_NOT_READY` |

`fetch_number_value` reads any finite number, whatever the class of the in-code default value: a whole number comes back as an Integer and any other number as a Float. `fetch_integer_value` reads whole numbers only, and `fetch_float_value` returns a Float.

The provider emits `PROVIDER_READY` once config has arrived, and `PROVIDER_CONFIGURATION_CHANGED` each time configs are updated, with the keys the update carried followed by the keys a full update removed.

## Tracking

`client.track` reports to ConfigDirector that something happened, such as a completed checkout, with the next telemetry batch: the details' `value` as the event's value, their other fields as the event's details, and the evaluation context as the context the event happened for. An event counts for an experiment only when its evaluation context has the targeting key the experiment's flag was evaluated with.

```ruby
client.track(
  "checkout-completed",
  evaluation_context: OpenFeature::SDK::EvaluationContext.new(targeting_key: "user-123"),
  tracking_event_details: OpenFeature::SDK::TrackingEventDetails.new(value: 49.9, plan: "pro")
)
```

`track` never raises. An event the provider cannot pass on, for example because its evaluation context cannot be read, is logged as a warning and not reported. It does nothing in offline mode.

## Test your code

Tests of code that reads flags through OpenFeature swap the provider for the in-memory one the OpenFeature Ruby SDK ships, `OpenFeature::SDK::Provider::InMemoryProvider`, so the test controls the values and nothing from ConfigDirector is involved:

```ruby
provider = OpenFeature::SDK::Provider::InMemoryProvider.new("new-checkout" => true)
OpenFeature::SDK.set_provider_and_wait(provider)
client = OpenFeature::SDK.build_client

expect(client.fetch_boolean_value(flag_key: "new-checkout", default_value: false)).to be(true)

provider.add_flag(flag_key: "new-checkout", value: false)
expect(client.fetch_boolean_value(flag_key: "new-checkout", default_value: true)).to be(false)
```

Shut OpenFeature down after each test with `OpenFeature::SDK.shutdown`.

## What the provider leaves out

- **The `STALE` and `FATAL` statuses.** A provider whose connection drops stays `READY` and serves the values it has, and a rejected server SDK key is reported as `ERROR`. Every ConfigDirector OpenFeature provider behaves this way today.
- **Flag metadata.** Evaluation details carry none, because a ConfigDirector evaluation has nothing to add beyond the reason and the variant.
- **The `hooks` option of `ConfigDirector.create_client`.** The provider handles its client's events itself; an application listens to OpenFeature's events instead. The provider adds no OpenFeature hooks of its own either.
- **Watches, reading every config at once and the `config_evaluated` event of the server SDK.** OpenFeature has no API for them; an application that needs them uses the [server SDK](https://github.com/ConfigDirector/ruby-sdks/tree/main/configdirector-server-sdk) directly.

## Documentation

Refer to the [official documentation for the OpenFeature Ruby provider](https://docs.configdirector.com/sdks/openfeature/ruby).

There is also [a quickstart guide for ConfigDirector and any of our SDKs](https://docs.configdirector.com/getting-started/quickstart).

## Getting Help

- [Ask a question in Discussions](https://github.com/orgs/ConfigDirector/discussions)
- [Contact support](https://www.configdirector.com/support)

[//]: # "links"
[ci-badge]: https://github.com/ConfigDirector/ruby-sdks/actions/workflows/ci.yml/badge.svg
[ci]: https://github.com/ConfigDirector/ruby-sdks/actions/workflows/ci.yml
[gem-badge]: https://img.shields.io/gem/v/configdirector-openfeature-server-provider
[gem]: https://rubygems.org/gems/configdirector-openfeature-server-provider
