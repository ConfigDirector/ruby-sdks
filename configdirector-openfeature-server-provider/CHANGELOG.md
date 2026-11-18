# Changelog

All notable changes to `configdirector-openfeature-server-provider` are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the gem uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-17

### Added

- `ConfigDirector::OpenFeature::ConfigDirectorProvider.new(server_sdk_key, metadata:, connection:, logger:,
  log_level:, telemetry:)`, required as `configdirector/openfeature`, an OpenFeature provider for
  `openfeature-sdk` 0.8.1 or later below 0.9, built on `configdirector-server-sdk` 0.1.0 or later below 1. It takes
  the options of `ConfigDirector.create_client` except `hooks`, raises what `create_client` raises, is named
  `ConfigDirectorProvider` to OpenFeature, and names itself `ruby-openfeature-server-provider` with its own version
  to ConfigDirector.
- The six typed reads of OpenFeature. A value served is a `TARGETING_MATCH` whose `variant` is the name of the
  variation served, or else the ID of the value; a percentage rollout skipped for a context without an identifier
  is a `DEFAULT` with the same `variant`; a config without a value is a `DEFAULT` without an error; a missing config
  is `FLAG_NOT_FOUND`, a value that cannot be read as the requested type `TYPE_MISMATCH`, and a read before any config
  arrives `PROVIDER_NOT_READY`. `fetch_number_value` reads any finite number, a whole number as an Integer and any
  other as a Float, whatever the class of the in-code default value.
- The evaluation context becomes a ConfigDirector context: the targeting key, or else an `id` attribute, and the
  `kind`, `name`, `traits` and `anonymous` attributes. An id or a name given as a Symbol, `true` or `false`, an
  Integer, a Float or a date is read as text, any other is left out, and a date is written as UTC text, inside the
  traits too.
- The provider reports its own `PROVIDER_READY` and `PROVIDER_ERROR` events. When no config arrives within the
  connection timeout, or ConfigDirector refuses the server SDK key, `set_provider_and_wait` raises
  `OpenFeature::SDK::ProviderInitializationError` with the error code `PROVIDER_NOT_READY` and the status is
  `ERROR`, until config arrives and the provider reports `PROVIDER_READY`. Offline values that cannot be loaded fail
  initialization with `GENERAL`.
- `PROVIDER_CONFIGURATION_CHANGED` each time configs are updated, with the keys the update carried followed by the
  keys it removed.
- `track` reports the event's value, its other fields as details and its evaluation context to ConfigDirector, and
  logs a warning instead of raising for an event it cannot pass on.
- `shutdown` closes the ConfigDirector client, which sends the telemetry it holds.
