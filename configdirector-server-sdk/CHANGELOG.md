# Changelog

All notable changes to `configdirector-server-sdk` are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the gem uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `ConfigDirector.create_client(server_sdk_key, metadata:, connection:, logger:, log_level:, telemetry:, hooks:)`
  creates a `ConfigDirector::ConfigDirectorClient` without making a network call. It raises
  `ConfigDirectorValidationError` when the server SDK key is missing or blank or `connection.url` is not an
  http or https URL, both outside offline mode only; when `connection.mode` is not `"streaming"`,
  `"polling"` or `"offline"`; when `connection.timeout` or `telemetry.flush_interval` is not a positive
  number; when `connection.polling_interval` is not a number; when `telemetry.event_queue_limit` is not a
  whole number from 100 to 100,000; when an option is not an object of its option class; when the `logger`
  lacks `debug`, `info`, `warn` or `error`; or when `log_level` is not a level of Ruby's `Logger` and no
  `logger` is given.
- The option objects `Metadata` (`app_name`, `app_version`), `ConnectionOptions` (`mode`, `polling_interval`,
  `timeout`, `url`, `file`, `values`), `TelemetryOptions` (`event_queue_limit`, `flush_interval`) and
  `ClientHooks`. Every duration is in seconds. In polling mode a `polling_interval` below 60 seconds is
  raised to 60 and a warning is logged. An option object cannot be changed once built.
- `init` waits for the first values, up to `connection.timeout`, and makes the client ready. When no values
  arrive in time it logs a warning and returns. `ready?` says whether the client has values to serve. Calling
  `init` again waits again and never opens a second connection.
- `get_value(config_key, default_value, context)` returns a config's value as the class of the in-code
  default value: `true` or `false`, a String, an Integer, a Float, a Hash for a JSON object or an Array for a
  JSON array. An Integer read accepts a whole number written as `26.0` or `1e3`. A `nil` in-code default
  value, or one of any other class, raises `ConfigDirectorValidationError`. A config key that is blank or
  not a String reads as a config that does not exist.
- `evaluate(...)` takes the same arguments and returns a `ConfigEvaluation` with `key`, `value`, `value_id`,
  `variation` (a `Variation` with `id` and `name`), `default_value?`, `reason` and `context`.
- The evaluation reasons, with the text every ConfigDirector SDK uses: `"found-match"`,
  `"rollout-skipped-no-identifier"`, `"config-state-missing"`, `"client-not-ready"`, `"type-mismatch"`,
  `"value-missing"`, `"invalid-number"`, `"invalid-json"` and `"invalid-boolean"`. Every reason but the first
  two returns the in-code default value.
- `Context.new(id:, kind:, name:, traits:, anonymous:)` is the user or other entity a config is evaluated
  for, and cannot be changed once built. An Integer `id` is read as its digits, and a Symbol key or value in
  `traits` is read as its text, so `{ plan: :pro }` is the trait `"plan"` with the value `"pro"`. Any other
  class for `id` or `name`, `traits` that are not a Hash, or an `anonymous` that is neither `true` nor
  `false` raises `ConfigDirectorValidationError`. A read given a context that is not a `Context`, such as a
  Hash, raises it too.
- A context whose `kind` is not 1 to 64 characters of lowercase letters, digits, `-` and `_` is ignored
  whole: the config is evaluated as if no context was given, the evaluation's `context` is `nil`, and an
  error is logged once for each invalid kind. After 20 different invalid kinds a client logs one more error
  and then no longer logs them.
- `get_all_configs(context:, config_keys:)` returns a `ConfigState` for every config, or for the listed
  config keys, keyed by config key. It is empty until the client is ready. A `ConfigState` has `id`, `key`,
  `type`, `value` (the served text), `value_id`, `variation`, `rule_id` and `share_id`. `config_keys` that
  are not an Array raise `ConfigDirectorValidationError`.
- `close` can be called more than once, and `closed?` says whether it was. Afterwards the client is not
  ready, every read returns its in-code default value with the reason `"client-not-ready"`,
  `get_all_configs` is empty, and `init` raises `ConfigDirectorValidationError`.
- `logger:` takes any object with the `debug`, `info`, `warn` and `error` methods of Ruby's `Logger`, such as
  `Rails.logger`, and calls each with one String. It writes no debug line through a logger whose `debug?`
  is false. Without a logger the SDK writes warnings and errors to standard error, and `log_level:` takes a
  level as Ruby's `Logger` does, such as `:debug`, to write more or less. `log_level:` has no effect when a
  `logger:` is given.
- `ConfigDirectorError` is the base class of every error the SDK raises, and `ConfigDirectorValidationError`
  extends it.
- `Context`, `Variation`, `ConfigState`, `ConfigEvaluation` and the option objects compare by value with
  `==`.
- Until the SDK connects to ConfigDirector, every client serves a fixed set of nine sample configs.
