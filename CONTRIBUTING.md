# Contributing

## Layout

This repository publishes two gems, each from a directory named after it:

- [configdirector-server-sdk](configdirector-server-sdk/), the server SDK, required as `configdirector`, with
  the module `ConfigDirector`. At runtime it depends on Ruby's standard library only. Its gemspec names two of
  the library's gems: `logger`, because Ruby 4.0 ships it as a bundled gem that Bundler no longer loads on its
  own, and `net-http` 0.10.0 or later, the first release that limits the head of an answer and each chunk size
  line to 1 MiB, where the `net/http` that Ruby 3.3 to 4.0 ship reads them into memory without a limit.
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

`samples/` holds sample applications, grouped by the gem they demonstrate. Each is its own Bundler project, with
its own `Gemfile` and committed `Gemfile.lock`, and its committed `.bundle/config` installs its gems into the
sample's `vendor/bundle` rather than into Ruby's gem directory: Homebrew's Ruby links the RubyGems plugin of `rdoc`
to a read-only file, so installing a newer `rdoc`, which every Rails application needs, into Homebrew's gem
directory fails with `Permission denied`. Until a gem's first release, its samples take it from this working tree
through a `path:` entry, which the release will replace with a released version. A sample's lock lists Linux and
macOS platforms only, unlike the gems' locks: the Rails sample runs Puma in cluster mode, which needs `fork`, so CI
runs the samples on Ubuntu alone, and on Windows the Makefile targets take `SAMPLES=`.

## Working on the gems

You need Ruby 3.4 or later, Bundler, and Docker for `make check-floor`. Every Ruby release we run ourselves must
have the regular expression fixes of 2026-10-23: 3.3.13, 3.4.12, 4.0.9 or a later release on the same line. On
macOS, `brew install ruby` installs a patched Ruby 4.0; Homebrew does not put it on your `PATH`, so add
`/opt/homebrew/opt/ruby/bin` in front of the system Ruby.

```sh
make install       # bundle install, every gem and sample
make hooks         # pre-push hook that runs make check-all
make check         # lint and test: the fast loop
make samples-local # the samples' suites against this working tree
make check-floor   # lint and test on each gem's oldest Ruby, in Docker
make check-all     # everything CI runs
make profile       # what an init, a read and a payload cost on this machine
```

Targets that run per gem take `GEMS`, so `make test GEMS=configdirector-server-sdk` runs one suite. `install`,
`verify-lock`, `format`, `lint`, `audit` and `clean` also run on each sample, which `SAMPLES=` leaves out, and
`make lint` runs RuboCop alone on a sample. `make samples-local` installs each sample's bundle and runs its suite,
which proves that a change to a gem has not broken the code an application writes against it.

`make lint` runs RuboCop, which checks each gem against the oldest Ruby its gemspec supports, then Steep, which
checks the code against the RBS signatures in `sig/`. The signatures ship in the gem. A finding is fixed, not
ignored: no file under `lib` is excluded from RuboCop, and no line disables a cop. `make format` applies RuboCop's
safe corrections. RSpec fails a run on a Ruby warning, on an RSpec warning or deprecation, and on an example left
focused, skipped or pending.

Three cops of the SDK are set apart in its `.rubocop.yml`:

- `Style/Documentation` checks the public API's files only, `lib/configdirector.rb`, `lib/configdirector/*.rb` and
  `lib/configdirector/testing/`, because the classes under `ConfigDirector::Internal` take no comments.
- `Naming/FileName` accepts snake_case names and `configdirector-server-sdk.rb`, the file named after the gem that
  `Bundler.require` loads.
- `Lint/InheritException` is off for the whole SDK, because of `StoppableThread::Stopped`: it stops an SDK thread
  and must not be caught by `rescue => e`, as the standard library's `Timeout::ExitException` must not.

YARD comments document the public API only. The one exception is the YARD tag `@api private` on the
`ConfigDirector::Internal` namespace, with the gem's `.yardopts`, which leaves that namespace out of the generated
documentation, so rubydoc.info shows the public API alone.

The SDK's lint also checks `spec/signature_fixture/`: code that reads values the way an application would, checked
against the gem's signatures. Its type errors are deliberate: each says which type the checker sees for a read, such
as `bool` for `get_value("new-checkout", false)`, and `steep_expectations.yml` lists them, so the check fails when
a signature stops typing a read by its in-code default value. After a change to the fixture, or a Steep release that
words a diagnostic differently, run `bundle exec steep check
--save-expectations=spec/signature_fixture/steep_expectations.yml` in the SDK's directory and read the diff.

`sig_missing_from_rbs/` in the SDK holds signatures of Ruby's own classes that the released `rbs` gem lacks: the
block of `Thread.handle_interrupt`, which `rbs` has on its main branch and 4.2.0 does not,
`Net::HTTP#ignore_eof`, which [ruby/rbs#3290](https://github.com/ruby/rbs/pull/3290) adds, and `Data#initialize`,
which the public value classes call with their keywords. Steep reads that
directory and the gem does not ship it. Delete a file there once an `rbs` release has its signature.

The SDK's specs that need an SDK server start `spec/support/scripted_sdk_server.rb`: a real HTTP server on a free
local port that holds each request until the example answers it, opens an event stream on it or drops it, and
is stopped when the example ends. It accepts a telemetry report at once and keeps it for the example to read, so
that closing a client never waits for an answer; an example that answers the reports itself calls
`hold_telemetry_reports` first. No spec stubs `net/http`. An example that needs to know how far the SDK read an
answer sends it in pieces: Windows takes one large write whole, whatever the other side reads, so only a later
write meets the connection the SDK closed.

The specs of a client in a forked process fork the process that runs RSpec. The forked process reports what it saw
through a pipe and leaves with `exit!`, so it runs none of RSpec's hooks and none of the examples that follow. Those
specs run wherever Ruby can fork, which in CI is Ubuntu and macOS, and are left out on Windows.

An example whose handler forks has to fork once only: each forked process opens its own stream, receives the first
values there and runs the same handler again, so a handler that forks every time forks without end. Set a flag
before the `fork`, which the forked process is copied with.

The SDK connects with Ruby's default certificate store and has no option to verify less, so a spec cannot make the
SDK in its own process trust a local certificate. `spec/support/self_signed_tls_listener.rb` is a TLS listener with
a self-signed certificate, and the examples that use it assert that the SDK ends the handshake and sends nothing.
Ruby builds the default store when `openssl` loads, from the file `SSL_CERT_FILE` names, so the one example that
needs a trusted TLS stream starts a process of its own with that variable set
(`spec/support/process_forking_in_a_handler_over_tls.rb`). It proves that a process forked inside a handler ends
without closing the stream it was copied with: closing it would send a TLS close notice on the parent's connection.

Three specs hold the SDK to what it must not do under load rather than to a behavior. The memory spec compares
the objects alive after a full garbage collection, early and late in a long run, and allows 5,000 objects of
drift. `spec/configdirector/internal/regular_expressions_spec.rb` gives every regular expression in the gem
100,000 characters written to make it backtrack and one second to answer: add an example there with every new
expression. The fork spec forks 200 times while the parent receives values and sends telemetry reports.

One example of the client's lifecycle runs on Ruby 4.0 and later only: the one that garbage collects a closed client.
The `timeout` library that Ruby 3.3 and 3.4 ship keeps the thread of a finished request reachable from its own
thread, and with it the client that thread worked for, so there the example would fail whatever the SDK holds.

One example of each transport does not run on Windows: the one that connects to an address that never answers.
Ruby on Windows calls Winsock's blocking `connect` (`rb_w32_connect` in Ruby's `win32/win32.c`), which neither
`Net::HTTP#open_timeout` nor `Thread#raise` can end, so there the attempt lasts until Windows gives up on it. A
`close` of the streaming transport during it returns after its 5 seconds while the streaming thread ends when the
attempt does, and a poll lasts as long as the attempt, the first poll included, which runs on the thread that
opens the polling transport.

`make verify-ruby` prints the version of the Ruby that runs it and fails when that release lacks the fixes above;
every CI job runs it first. `make verify-lock` fails when a `Gemfile.lock` no longer matches its `Gemfile` and
gemspec. `make build` builds each gem into `dist/` with `gem build --strict`, which fails on any warning about the
gemspec. `make audit` runs `bundle-audit` against each lock with the latest advisory database.

`make test-lowest` runs the suites with each runtime dependency of the gemspec at the lowest version the gemspec
allows, such as `logger` 1.6 for `~> 1.6`, so they fail when the code needs something newer than that floor.
Bundler resolves those versions into a throwaway `Gemfile` and lock, so the committed locks stay as they are.

`make check-floor` runs `make verify-ruby verify-lock lint test` for each gem in the official image of its oldest
Ruby line, `ruby:3.3` for the SDK and `ruby:3.4` for the provider, pulled again on every run so that it is the
newest release of that line, on a copy of this working tree.

CI runs the SDK's suite on Ruby 3.3, 3.4 and 4.0 on Ubuntu, on Ruby 4.0 on macOS, and on Ruby 3.3 and 4.0 on
Windows, the provider's suite on Ruby 3.4 and 4.0 on Ubuntu, the samples' suites on Ruby 3.3 and 4.0 on Ubuntu,
and `make test-lowest`, the lint, build and audit on Ruby 4.0. Locally, `make check-all` covers your own Ruby and,
through `make check-floor`, each gem's oldest Ruby line.

The checks live in the [Makefile](Makefile). CI and the pre-push hook only call `make` targets, so add new checks
there rather than in either of them.

`profiling/` holds two measurements of the SDK against a local SDK server, `make profile` and
`make profile-fork-per-job`, described in its [README](profiling/README.md). They are not checks, so `make check-all`
does not run them, but `make lint` runs RuboCop on them with the SDK.

## How the provider identifies itself

The SDK reports an SDK name and version in the `User-Agent` header and in the `metaContext` of every request for
values, and will report them in telemetry: `ruby-server-sdk` and `ConfigDirector::VERSION`. A gem built on the SDK,
such as the provider, reports its own name and version, `ruby-openfeature-server-provider` and
`ConfigDirector::OpenFeature::VERSION`, without the SDK accepting an arbitrary identity from its caller: the SDK
keeps a closed list of the gems allowed to, `ConfigDirector::Internal::Identity::Wrapper`. Its one entry creates a
client that reports the provider:

```ruby
ConfigDirector::Internal::Identity::Wrapper::OPENFEATURE_SERVER_PROVIDER.create_client(server_sdk_key, logger: logger)
```

`create_client` there takes the arguments of `ConfigDirector.create_client`. The version is read when the client is
created, and is `0.0.0-dev` while the wrapper's gem is not loaded. The list is not public API. Adding a wrapper gem
means adding it to that list, releasing the SDK, and registering the new name in the ConfigDirector capability
tables.

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
