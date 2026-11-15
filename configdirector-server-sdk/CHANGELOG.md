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
  `ClientHooks` (`client_ready`, `configs_updated`, `config_evaluated`, `connection_error`). Every duration is in
  seconds. In polling mode a `polling_interval` below 60 seconds is
  raised to 60 and a warning is logged. An option object cannot be changed once built.
- The client connects to ConfigDirector at `connection.url`. In `"streaming"` mode, the default, it keeps a
  connection open and receives a new value as soon as it changes in ConfigDirector, and it reconnects by itself
  when the connection drops. In `"polling"` mode it asks for new values every `polling_interval`, and
  `connection.timeout` is also how long each of those requests may take. In `"offline"` mode it makes no network
  call and is ready after `init`; for now an offline client serves no values, so every read returns its in-code
  default value with the reason `"config-state-missing"`.
- `init` connects and makes the client ready. It waits, up to `connection.timeout`, for the first values and for
  their handlers and watches to finish. When no values arrive in time it logs a warning and returns, and the
  client keeps trying. It never raises because the connection failed. `ready?` says whether the client has
  values to serve. Calling `init` again waits again and never opens a second connection.
- When ConfigDirector refuses the connection, for example because it does not know the server SDK key, the client
  logs an error, calls the `connection_error` handlers once and does not try again. An `init` that is waiting
  returns at once, without the warning, and so does a later `init`. A client that was ready keeps serving the
  values it has.
- In polling mode, `init` returns as soon as the first request for values has failed, with the failure logged as
  an error, and the client asks again after the polling interval.
- A config or segment whose definition the SDK cannot read is skipped with a warning, and every other config is
  served. A read of a skipped config returns its in-code default value with the reason `"config-state-missing"`,
  and a client that served the config before names it in the `removed_keys` of `configs_updated`. Fields the SDK
  does not know are ignored.
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
- `ConfigDirectorConnectionError` extends `ConfigDirectorError` and describes a failure to get values from
  ConfigDirector. Its `status` is the HTTP status ConfigDirector answered with, or `nil` when there was no
  answer, and it is built as `ConfigDirectorConnectionError.new(message, status: 401)`. It is the `error` of the
  `ConnectionErrorEvent` a `connection_error` handler receives.
- `on(event_name, handler)` registers a handler for one of four events, `:client_ready`, `:configs_updated`,
  `:config_evaluated` and `:connection_error`, and returns a `Subscription`. The handler is a block or any object
  that responds to `call`, such as a lambda or `method(:name)`, and a handler registered twice runs twice. Any
  other event name, a String such as `"configs_updated"` included, raises `ConfigDirectorValidationError`, as do a
  handler and a block given together, neither of them, or a handler that does not respond to `call`.
- `off(event_name, handler)` removes the first registration of a handler equal to `handler`, so `method(:name)`
  finds a handler registered as `method(:name)`, or every handler of the event, hooks included, when `handler` is
  left out.
- `client_ready` handlers are called with no argument once, when the client first receives values and becomes
  ready. `configs_updated` handlers receive a `ConfigsUpdatedEvent` each time the client receives values: its
  `keys` are the configs received, in the order ConfigDirector sent them, followed by the configs whose targeting
  rules use a segment that was received, and its `removed_keys` the configs the client no longer serves because
  the values received left them out. `config_evaluated` handlers receive a `ConfigEvaluatedEvent` with the
  `evaluation` of every `get_value`, `evaluate` and watch, before the read returns; `get_all_configs` calls none
  of them. `connection_error` handlers receive a `ConnectionErrorEvent` with the `error`.
- `ClientHooks.new(client_ready:, configs_updated:, config_evaluated:, connection_error:)` takes one handler or an
  Array of handlers per event. `create_client` registers them in the order given, before any handler registered
  with `on`. An entry that does not respond to `call` is ignored and a warning is logged.
- `watch(config_key, default_value, context) { |value| ... }` calls the block with the config's value each time
  the client receives values that include the config or a segment its targeting rules use, even when its value
  is the same, and with the in-code default value when they leave it out. It never calls the block when the
  watch is registered, so a watch registered before `init` receives the first value during it. It returns a
  `Subscription`. A missing block, an in-code default value `get_value` would reject, or a context that is not
  a `Context` raises `ConfigDirectorValidationError`.
- `unwatch(config_key, callback)` removes the first watch on the key whose block is `callback`, the same Proc or
  lambda, or every watch on the key when `callback` is left out. `unwatch_all` removes every watch.
- `Subscription#close` removes the handler or watch it registered, and only that one, even when the same handler
  or block was registered again. It can be called more than once, and `closed?` says whether it was.
- Each time the client receives values, the `configs_updated` handlers run first, then the watches on the keys
  received and then on the keys removed, then the `client_ready` handlers when the client has just become ready.
  They run on the thread that received the values: a thread of the SDK in streaming mode, and in polling mode
  the thread that called `init` for the first request and a thread of the SDK for every later one. In offline
  mode it is the thread that called `init`.
  `connection_error` handlers run on those threads too, and `config_evaluated` handlers on the thread that read.
  A handler or watch can read from the client.
- A handler or watch that raises a `StandardError` is logged at error level and ignored: the other handlers and
  watches still run and the read still returns its value.
- `close` also removes every handler, hook and watch.
- `Context`, `Variation`, `ConfigState`, `ConfigEvaluation`, `ConfigsUpdatedEvent`, `ConfigEvaluatedEvent`,
  `ConnectionErrorEvent` and the option objects compare by value with `==`, and cannot be changed once built.
- A client on which `init` was called before the process forked, as under Puma in cluster mode, Unicorn or
  Passenger, starts its own connection in the forked process by itself. It serves the values it was copied with at
  once, and handlers and watches registered before the fork keep firing there. The parent's connection is not
  affected. A client that was never initialized, was closed, was refused by ConfigDirector, or is offline does
  nothing at a fork.
