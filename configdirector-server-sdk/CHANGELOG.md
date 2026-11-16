# Changelog

All notable changes to `configdirector-server-sdk` are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the gem uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `ConfigDirector.create_client(server_sdk_key, metadata:, connection:, logger:, log_level:, telemetry:, hooks:)`
  creates a `ConfigDirector::ConfigDirectorClient` without making a network call. It raises
  `ConfigDirectorValidationError` when the server SDK key is missing or blank, `connection.url` is not an
  http or https URL, `connection.timeout` is not a positive number, or `connection.file` or `connection.values`
  is given, all outside offline mode only; when `connection.mode` is not `"streaming"`, `"polling"` or
  `"offline"`; when `telemetry.flush_interval` is not a positive number; when `connection.timeout` or
  `connection.polling_interval` is not a number; when `telemetry.event_queue_limit` is not a whole number from
  100 to 100,000; when an option is not an object of its option class; when the `logger` lacks `debug`, `info`,
  `warn` or `error`; or when `log_level` is not a level of Ruby's `Logger` and no `logger` is given.
- The option objects `Metadata` (`app_name`, `app_version`), `ConnectionOptions` (`mode`, `polling_interval`,
  `timeout`, `url`, `file`, `values`), `TelemetryOptions` (`event_queue_limit`, `flush_interval`) and
  `ClientHooks` (`client_ready`, `configs_updated`, `config_evaluated`, `connection_error`). Every duration is in
  seconds. In polling mode a `polling_interval` below 60 seconds is
  raised to 60 and a warning is logged. An `app_name` or `app_version` that is not a String, such as the build
  number `2`, is read as its text, `"2"`. An option object cannot be changed once built.
- The client connects to ConfigDirector at `connection.url`. In `"streaming"` mode, the default, it keeps a
  connection open and receives a new value as soon as it changes in ConfigDirector, and it reconnects by itself
  when the connection drops. In `"polling"` mode it asks for new values every `polling_interval`, and
  `connection.timeout` is also how long each of those requests may take.
- In `"offline"` mode the client needs no server SDK key, never connects to ConfigDirector and sends nothing,
  and serves one value per config key to every context, without applying targeting rules. The values are given
  inline as `connection.values`, such as `{ "new-checkout": true, "max-items": 20 }`, or as `connection.file`, the
  path of a JSON object of config key to value, given as a String or a Pathname and resolved against the working
  directory. With neither, every read returns its in-code default value with the reason
  `"config-state-missing"`. `connection.timeout` has no effect, and zero or less is accepted.
- The config type of an offline value follows from its class: `true` or `false` is a boolean, an Integer an
  integer, a Float a float written as plain decimal text (`25.0` as `25`, `1.0e-7` as `0.0000001`), a String a
  string, and a Hash or an Array a JSON config in compact JSON, which can hold `nil`. A key is a String or a
  Symbol, and a Symbol, in the values or in a Hash inside a JSON value, is read as its name. A String in another
  encoding is converted to UTF-8, and a binary String whose bytes are UTF-8 text is read as that text. A served
  offline value has the reason `"found-match"`, no value ID and no variation, and its config ID is `offline:`
  followed by the key.
- `create_client` raises `ConfigDirectorValidationError` when `connection.file` and `connection.values` are both
  given, when `connection.values` is not a Hash, or when `connection.file` is neither a String nor a Pathname. It
  raises it too when the values hold a key that is blank, of another class, not UTF-8 text, or given twice, such
  as a String and a Symbol with the same name, or a value the SDK cannot serve: `nil`, a Float that is not finite,
  a String that is not UTF-8 text, or an object of another class, such as a Symbol or a Time. A JSON value can
  hold `nil`, and the same rules apply to every value and Hash key inside it. A JSON value nested deeper than 100
  levels is rejected, and so is one that holds itself.
- In offline mode `init` reads the file again each time it is called, and reads never read it. Each `init` calls
  the `configs_updated` handlers with every key the values hold and, in `removed_keys`, the keys the file no
  longer holds, then their watches, and the `client_ready` handlers the first time the client becomes ready. An
  `init` that a handler calls during an `init` returns at once. An offline client starts no thread, and in a
  forked process it serves its values with nothing to restart.
- `ConfigDirectorInitializationError` extends `ConfigDirectorError`. In offline mode `init` raises it, and logs
  nothing, when the file cannot be read, is not UTF-8 text, is not valid JSON, is not a JSON object, or holds a
  value the SDK cannot serve. A client that was not ready stays not ready, and one that was ready keeps serving
  the values it had and stays ready.
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
  `false` raises `ConfigDirectorValidationError`. So do `traits` nested deeper than 100 levels, which a Hash or
  an Array that holds itself is. A read given a context that is not a `Context`, such as a Hash, raises it too.
- A context whose `kind` is not 1 to 64 characters of lowercase letters, digits, `-` and `_` is ignored
  whole: the config is evaluated as if no context was given, the evaluation's `context` is `nil`, and an
  error is logged once for each invalid kind until the client next sends its telemetry. A client that reports
  every `telemetry.flush_interval` logs a kind that keeps being given about once per interval. After 20
  different invalid kinds a client logs one more error and then no longer logs them until that report is sent.
  An offline client and the client of a test client, which send no telemetry, log the error on every read.
- `get_all_configs(context:, config_keys:)` returns a `ConfigState` for every config, or for the listed
  config keys, keyed by config key. It is empty until the client is ready. A `ConfigState` has `id`, `key`,
  `type`, `value` (the served text), `value_id`, `variation`, `rule_id` and `share_id`. `config_keys` that
  are not an Array raise `ConfigDirectorValidationError`.
- The client reports what it evaluates to ConfigDirector, which shows it as activity in the dashboard and counts
  the exposures of experiments from it. Each `get_value`, `evaluate` and watch delivery is one evaluation, reads
  that return the in-code default value included, and identical evaluations are sent once with their count.
  `get_all_configs` and reads after `close` are not reported. A context that has an `id` and is not anonymous is
  sent with its `name` and `traits`, once per report. A context with an invalid kind is only counted, with a
  sample of its kind and nothing else of it.
- The first `init` starts a thread of the SDK that sends the first report 5 seconds later and then one every
  `telemetry.flush_interval`, 30 seconds unless given. A client that was created and never initialized starts no
  thread and keeps what it evaluated until `init` or `close`. Between two reports the client holds at most
  `telemetry.event_queue_limit` events, 5,000 unless given: evaluations up to 70% of it and contexts up to 30%.
  Beyond that it drops the oldest and reports how many it dropped. An offline client reports nothing.
- `close` sends what the client evaluated since its last report before it returns. It waits up to 5 seconds for
  ConfigDirector to answer, and up to 5 more when a report was already being sent. The SDK registers no exit hook,
  so a process that exits without calling `close` does not report its last reads.
- When ConfigDirector refuses a report with a status from 400 to 499 other than 413 and 429, for example because
  it does not know the server SDK key, the client logs a warning and collects and sends no more telemetry. A report
  that fails any other way is logged as a warning and discarded, and the next one is sent on time. No report is
  sent twice.
- In a forked process, a client that starts its own connection there also reports from there what that process
  evaluates, with its first report 5 seconds after the fork. What was evaluated before the fork is reported once,
  by the parent. After `Process.daemon`, where the original process ends at once, such a client reports what was
  evaluated before it from the process `Process.daemon` leaves.
- `track(event_name, context = nil, value: nil, details: nil)` reports to ConfigDirector that something happened,
  such as a completed checkout, so experiments can count it. The event is sent with the next report, with the time
  of the call, and `close` sends the events tracked since the last one. `track` returns `nil`, never raises, and
  does nothing in offline mode or once the client is closed. A Symbol name is read as its name. The context's kind
  and `id` are sent when it has an `id` and is not anonymous, and it is not added to the reported contexts. A
  context with an invalid kind is logged and counted as for a read, and the event is sent without it; a context
  that is not a `Context` drops the event with a warning.
- An event whose name does not have 1 to 150 characters is dropped, and so are the events beyond the first 1,000
  of a report. A `value` is sent when it is a finite Float or an Integer no larger than the largest Float, and
  left out otherwise. `details` are left out when they are not a Hash, have more than 20 top-level keys, are
  larger than 1,024 bytes as JSON, are nested deeper than 100 levels, or hold anything but Strings, numbers,
  `true`, `false`, `nil`, Symbols, Times and Arrays and Hashes of them with String or Symbol keys. A Symbol is
  sent as its name, a Time as its ISO 8601 text in UTC, and a Float that is not finite as `null`. The event is
  still sent without what was left out. Each of these logs one warning per report.
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
  `ConnectionErrorEvent`, `Testing::TrackedEvent` and the option objects are Ruby `Data` objects: they compare by
  value with `==`, cannot be changed once built, and offer `with`, which checks the new values as `new` does,
  `to_h` and pattern matching, such as `case evaluation in { reason: "found-match" }`.
  Whether a context is anonymous is read with `anonymous?`, and whether an evaluation returned the in-code default
  value with `default_value?`.
- `ConfigDirectorClient#inspect` shows the connection mode and whether the client is ready and closed, such as
  `#<ConfigDirector::ConfigDirectorClient mode="streaming" ready=true closed=false>`, with the mode `"test"` for the
  client of a test client, and never the server SDK key; `pp` and the Rails console show the same.
- The RBS signatures in the gem type `get_value`, `evaluate` and the block of `watch` by the class of the in-code
  default value, so a type checker such as Steep sees `get_value("new-checkout", false)` as a boolean and
  `get_value("checkout-settings", {})` as a Hash with String keys. A Hash in-code default value with Symbol keys is
  typed as a Hash with String or Symbol keys, since the read returns it as given when it falls back to it.
- A client on which `init` was called before the process forked, as under Puma in cluster mode, Unicorn or
  Passenger, starts its own connection in the forked process by itself. It serves the values it was copied with at
  once, and handlers and watches registered before the fork keep firing there. The parent's connection is not
  affected. A client that was never initialized, was closed, was refused by ConfigDirector, or is offline does
  nothing at a fork.
- A fork is safe at any moment: while values arrive, while a telemetry report is being sent, while another thread
  is in `init`, and from a signal handler that interrupted a call into the client. The forked process starts its
  connection on a thread of the SDK right after the fork, and `fork` does not wait for it.
- A process that a `configs_updated`, `client_ready` or `connection_error` handler or a watch forked without a
  block, on a thread of the SDK, can read from the client inside that handler. It ends when the handler returns
  in it, with exit status 0 and its `at_exit` hooks, as it would after the block of `fork { }`, and the parent
  keeps receiving every update.
- A request for values in polling mode ends when `connection.timeout` has passed, and a telemetry report after 5
  seconds, counted from before the connection opens, even while ConfigDirector keeps sending an answer that never
  completes.
- The gem depends on `net-http` 0.10.0 or later, the first release that limits the head of an HTTP answer and
  each chunk size line to 1 MiB, so an application's lock gains `net-http`, `net-protocol`, `timeout` and `uri`.
  When an answer passes that limit, a stream reconnects, and a request for values in polling mode or a telemetry
  report counts as one that failed.
- Values that hold a number of more than 16,384 digits are not read, and ConfigDirector stores no value that
  long. Such a message of the stream is skipped with an error and the client keeps the values it has, such an
  answer to a request for values in polling mode is a failed request, a JSON config with such a value returns
  the in-code default value with the reason `"invalid-json"`, and an integer config with such a value returns it
  with `"invalid-number"`.
- The error the client logs for a message of the stream that is not JSON says `it is not valid JSON` and never
  repeats the message, so a message that repeats the server SDK key does not put it in the log.
- `require "configdirector/testing"` loads `ConfigDirector::Testing.create_test_client(values, timeout:, logger:)`,
  which returns a `ConfigDirector::Testing::TestClient` for testing code that reads configs. Its `client` is the
  SDK's real client over an in-memory connection the test controls: it needs no server SDK key, opens no network
  connection, starts no thread and sends nothing. The values follow the offline typing rule, and every context
  receives the same value as a `"found-match"` with no value ID and no variation, from a config whose ID is
  `test-config:` followed by the key. `timeout` is how long a held `init` waits, 3 seconds unless given.
  `create_test_client`, `set_value` and `replace_values` raise `ConfigDirectorValidationError` for values the SDK
  cannot serve, changing nothing, and `create_test_client` raises it too for a timeout that is not a positive
  number or a logger without the four methods.
- `TestClient#set_value(key, value)` delivers an update that carries only that key, and `remove_value(key)` and
  `replace_values(values)` deliver a full update, before they return, with the handlers and watches run on the
  calling thread; a change made while the client is not connected reaches it with the next `init`. A change made
  from inside a handler or a watch is delivered right after the one being handled. `replace_values` also cancels a
  hold or a failure that no `init` has used.
- `TestClient#hold_initialization` makes the next `init` wait until another thread calls `complete_initialization`,
  which delivers the stored values on its own thread, or `fail_initialization`, or until the timeout, when `init`
  logs the timeout warning and returns. `fail_initialization` fails a held `init`, or makes the next one fail: one
  error is logged and the `connection_error` handlers receive a `ConfigDirectorConnectionError` of status 401, each
  time, and then the failed `init` returns, at once when nothing held it. A client that was ready keeps serving its
  values through a held or failed `init`.
- `TestClient#tracked_events` returns every event the code under test tracked through the client, in call order, as
  `ConfigDirector::Testing::TrackedEvent` (`name`, `context`, `value`, `details`), which compares by value. It
  follows the rules of a real report and logs each warning every time; the limit of 1,000 per report does not apply,
  and nothing is recorded once the client is closed. The details are recorded as the SDK sends them, with String
  keys. It is the same Array on every call and grows as events are tracked, so a test can empty it with `clear`.
