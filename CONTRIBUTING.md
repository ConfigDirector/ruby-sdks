# Contributing

## Layout

This repository publishes two gems, each from a directory named after it:

- [configdirector-server-sdk](configdirector-server-sdk/), the server SDK, required as `configdirector`, with
  the module `ConfigDirector`. At runtime it depends on Ruby's standard library only, and names the `logger`
  gem in its gemspec, because Ruby 4.0 ships `logger` as a bundled gem that Bundler no longer loads on its own.
- [configdirector-openfeature-server-provider](configdirector-openfeature-server-provider/), the OpenFeature
  provider built on it, required as `configdirector/openfeature`, with the module `ConfigDirector::OpenFeature`.

Each gem has its own gemspec, `Gemfile`, `Gemfile.lock` and development tools, because the two support
different Ruby versions: the SDK supports Ruby 3.3 and later, and the provider 3.4 and later, which
`openfeature-sdk` requires. Each has its own version, changelog, and release.

Each gem also ships a file named after the gem, such as `lib/configdirector-server-sdk.rb`, that requires its
entry point. `Bundler.require`, which a Rails application calls at startup, requires a gem by its gem name, so an
application loads the gem without a `require:` option in its `Gemfile`.

The provider's `Gemfile` takes the SDK from its directory in this working tree, so the provider always develops
against the SDK beside it. Before the provider's first release, its gemspec has to name a released version range
of the SDK instead of the exact development version.

The lock files are committed. `make install` updates a lock after a change to its `Gemfile` or gemspec, and
`make check-floor` proves the lock still installs, unchanged, on the gem's oldest Ruby line. Each lock lists the
platforms we run on, Windows (`x64-mingw-ucrt`) among them, so that every runner installs the prebuilt builds of
native gems such as `ffi` and `prism` instead of compiling them. Bundler adds the Linux and macOS platforms by
itself; after adding a dependency, check that `PLATFORMS` in the lock still lists `x64-mingw-ucrt`, and add it
with `bundle lock --add-platform x64-mingw-ucrt` if not.

Each gemspec reads its version from the text of its `version.rb` rather than requiring the file. Bundler loads
the gemspec of a gem named by its path before `Bundler.require` runs, so a required `version.rb` would define the
gem's module before the gem is loaded.

`samples/` is reserved for sample applications. They will install the gems the way an application does.

## Working on the gems

You need Ruby 3.4 or later, Bundler, and Docker for `make check-floor`. Every Ruby release we run ourselves must
have the regular expression fixes of 2026-10-23: 3.3.13, 3.4.12, 4.0.9 or a later release on the same line. On
macOS, `brew install ruby` installs a patched Ruby 4.0; Homebrew does not put it on your `PATH`, so add
`/opt/homebrew/opt/ruby/bin` in front of the system Ruby.

```sh
make install     # bundle install, every gem
make hooks       # pre-push hook that runs make check-all
make check       # lint and test: the fast loop
make check-floor # lint and test on each gem's oldest Ruby, in Docker
make check-all   # everything CI runs
```

Targets that run per gem take `GEMS`, so `make test GEMS=configdirector-server-sdk` runs one suite.

`make lint` runs RuboCop, which checks each gem against the oldest Ruby its gemspec supports, then Steep, which
checks the code against the RBS signatures in `sig/`. The signatures ship in the gem. A finding is fixed, not
ignored. `make format` applies RuboCop's safe corrections. RSpec fails a run on a Ruby warning, on an RSpec
warning or deprecation, and on an example left focused, skipped or pending.

`make verify-ruby` prints the version of the Ruby that runs it and fails when that release lacks the fixes above;
every CI job runs it first. `make verify-lock` fails when a `Gemfile.lock` no longer matches its `Gemfile` and
gemspec. `make build` builds each gem into `dist/` with
`gem build --strict`, which fails on any warning about the gemspec. `make audit` runs `bundle-audit` against
each lock with the latest advisory database.

`make check-floor` runs `make verify-ruby verify-lock lint test` for each gem in the official image of its oldest
Ruby line,
`ruby:3.3` for the SDK and `ruby:3.4` for the provider, pulled again on every run so that it is the newest release
of that line, on a copy of this working tree.

CI runs the SDK's suite on Ruby 3.3, 3.4 and 4.0 on Ubuntu and on Ruby 4.0 on macOS and Windows, the provider's
suite on Ruby 3.4 and 4.0 on Ubuntu, and the lint, build and audit on Ruby 4.0. Locally, `make check-all` covers
your own Ruby and, through `make check-floor`, each gem's oldest Ruby line.

The checks live in the [Makefile](Makefile). CI and the pre-push hook only call `make` targets, so add new checks
there rather than in either of them.

## How the provider identifies itself

The SDK will report an SDK name and version in the `User-Agent` header and in telemetry: `ruby-server-sdk` and
`ConfigDirector::VERSION`. A gem built on the SDK, such as the provider, will report its own name and version,
`ruby-openfeature-server-provider` and `ConfigDirector::OpenFeature::VERSION`, without the SDK accepting an
arbitrary identity from its caller: the SDK will keep a closed list of the gems allowed to. This list does not
exist yet; it will arrive with the provider. Adding a wrapper gem will mean adding it to that list, releasing the
SDK, and registering the new name in the ConfigDirector capability tables.

## Releasing

Each gem is released on its own. Its version lives in exactly one place, its `VERSION` constant, which the gemspec
reads:

| Gem | Version | Changelog |
|---|---|---|
| configdirector-server-sdk | [`version.rb`](configdirector-server-sdk/lib/configdirector/version.rb) | [CHANGELOG.md](configdirector-server-sdk/CHANGELOG.md) |
| configdirector-openfeature-server-provider | [`version.rb`](configdirector-openfeature-server-provider/lib/configdirector/openfeature/version.rb) | [CHANGELOG.md](configdirector-openfeature-server-provider/CHANGELOG.md) |

Until its first release a gem's `VERSION` is `0.1.0-dev`. RubyGems writes the dash as `.pre.`, so the gem is
built as `0.1.0.pre.dev`, while the SDK will report `VERSION` itself. A development version has to sort above `0`:
Bundler matches a gem named in a `Gemfile` without a version against `>= 0`, and RubyGems sorts `0.0.0.pre.dev`
below it, so a `Gemfile` that names a gem at `0.0.0-dev` by its path does not resolve.

The release workflow and the steps to run it are not written yet; this section will describe them once they are.

### Version line

The gems stay at `0.x` until the SDK functional tests pass against them in dev, which is when `1.0.0` is
released.
