# Changelog

All notable changes to `configdirector` are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the gem uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The gem installs `configdirector-server-sdk`, the Ruby server SDK for ConfigDirector, in any `0.x` version from
  `0.1.0`, and holds no code of its own. `require "configdirector"` loads the SDK.
