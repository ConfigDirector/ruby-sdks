# Contributing

## Layout

This repository publishes three gems, each from a directory named after it:

- [configdirector-server-sdk](configdirector-server-sdk/), the server SDK, required as `configdirector`, with
  the module `ConfigDirector`. At runtime it depends on Ruby's standard library only. Its gemspec names two of
  the library's gems: `logger`, because Ruby 4.0 ships it as a bundled gem that Bundler no longer loads on its
  own, and `net-http` 0.10.0 or later, the first release that limits the head of an answer and each chunk size
  line to 1 MiB, where the `net/http` that Ruby 3.3 to 4.0 ship reads them into memory without a limit.
- [configdirector-openfeature-server-provider](configdirector-openfeature-server-provider/), the OpenFeature
  provider built on it, required as `configdirector/openfeature`, with the module `ConfigDirector::OpenFeature`.
- [configdirector](configdirector/), which holds the bare name on RubyGems so that nobody else can publish under
  it. It has no code: it depends on the SDK in any `0.x` version from `0.1.0`, so `gem install configdirector`
  installs the SDK, and `require "configdirector"` loads the SDK's own entry point. It has a gemspec, a README, a
  changelog and a license, and nothing to lint or test, so of the Makefile targets only `build`, `release-check`
  and `test-release` know it. It must never ship a `lib/configdirector.rb`, which would be loaded in place of the
  SDK's.

The SDK and the provider each have their own gemspec, `Gemfile`, `Gemfile.lock` and development tools, because the
two support different Ruby versions: the SDK supports Ruby 3.3 and later, and the provider 3.4 and later, which
`openfeature-sdk` requires. Each of the three gems has its own version, changelog, and release.

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
make test-release  # the release scripts, against throwaway repositories and a stand-in for RubyGems
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
gemspec, and then checks what each built gem holds: see [What a release publishes](#what-a-release-publishes).
`make audit` runs `bundle-audit` against each lock with the latest advisory database.

`make test-lowest` runs the suites with each runtime dependency of the gemspec at the lowest version the gemspec
allows, such as `logger` 1.6 for `~> 1.6`, so they fail when the code needs something newer than that floor.
Bundler resolves those versions into a throwaway `Gemfile` and lock, so the committed locks stay as they are.

`make check-floor` runs `make verify-ruby verify-lock lint test` for each gem in the official image of its oldest
Ruby line, `ruby:3.3` for the SDK and `ruby:3.4` for the provider, pulled again on every run so that it is the
newest release of that line, on a copy of this working tree.

CI runs the SDK's suite on Ruby 3.3, 3.4 and 4.0 on Ubuntu, on Ruby 4.0 on macOS, and on Ruby 3.3 and 4.0 on
Windows, the provider's suite on Ruby 3.4 and 4.0 on Ubuntu, the samples' suites on Ruby 3.3 and 4.0 on Ubuntu,
and `make test-lowest`, the lint, `make test-release`, the build and the audit on Ruby 4.0. Locally, `make check-all` covers your own Ruby and,
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

Each gem is released on its own, by a workflow of its own, and the steps are the same for all three. A gem's
version lives in exactly one place:

| Gem | Version | Changelog | Workflow |
|---|---|---|---|
| configdirector-server-sdk | `VERSION` in [`version.rb`](configdirector-server-sdk/lib/configdirector/version.rb) | [CHANGELOG.md](configdirector-server-sdk/CHANGELOG.md) | [Release configdirector-server-sdk](.github/workflows/release-configdirector-server-sdk.yml) |
| configdirector-openfeature-server-provider | `VERSION` in [`version.rb`](configdirector-openfeature-server-provider/lib/configdirector/openfeature/version.rb) | [CHANGELOG.md](configdirector-openfeature-server-provider/CHANGELOG.md) | [Release configdirector-openfeature-server-provider](.github/workflows/release-configdirector-openfeature-server-provider.yml) |
| configdirector | `spec.version` in [`configdirector.gemspec`](configdirector/configdirector.gemspec) | [CHANGELOG.md](configdirector/CHANGELOG.md) | [Release configdirector](.github/workflows/release-configdirector.yml) |

Until its first release a gem's version is `0.1.0-dev`. RubyGems writes the dash as `.pre.`, so the gem is
built as `0.1.0.pre.dev`, while the SDK reports `VERSION` itself. A development version has to sort above `0`:
Bundler matches a gem named in a `Gemfile` without a version against `>= 0`, and RubyGems sorts `0.0.0.pre.dev`
below it, so a `Gemfile` that names a gem at `0.0.0-dev` by its path does not resolve.

1. In the gem's changelog, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and open a fresh, empty
   `## [Unreleased]` above it.
2. Set the gem's version to `X.Y.Z`, run `make install`, which writes the new version into the lock files that
   name the gem, and merge all of it to `main`.
3. Run the gem's release workflow against `main`; it refuses any other branch. It is manual
   (`workflow_dispatch`) by design and releases whatever version `main` declares. It reads the version from the
   gemspec and refuses to go on when the version is not `X.Y.Z`, when the tag `<gem>-vX.Y.Z` already exists, when
   RubyGems already has that version, or when the changelog has no section for it (an empty section counts as
   none). It then runs `make release-check` and `make check-all`, builds the gem on a fresh checkout and checks
   what it holds, pushes it to RubyGems, tags the released commit `<gem>-vX.Y.Z`, for example
   `configdirector-server-sdk-v0.1.0`, and creates a GitHub Release with the changelog section as its notes.

With **dry_run** checked, the workflow runs every check, has RubyGems accept it as the gem's trusted publisher, and
stops there: it pushes nothing and creates no tag. Run it that way before the first release of a gem, and after
any change to the publish job, the `release` environment or the trusted publisher on RubyGems. A dry run needs the
version and the changelog section of step 1 and 2 on `main`, because it starts with the same refusals.

A version is `X.Y.Z`. The workflow releases no prerelease, and RubyGems never accepts a version twice, a yanked
one included: to ship a fix, raise the version, add a changelog section and release again.

Release the SDK before a gem that needs it. The provider and `configdirector` each name the SDK versions they work
with in their gemspec, and `make release-check GEM=<gem>` installs the built gem into an empty gem home with its
dependencies from RubyGems, then loads it by the name `Bundler.require` uses. So their workflows stop before
publishing while RubyGems does not serve an SDK version in that range. `configdirector` needs a release of its
own only when its range of SDK versions changes: at the SDK's `1.0.0`.

The push to RubyGems is the release. When a step before it fails, nothing is published: fix the cause and run the
workflow again. When the tag or the GitHub Release fails after the push, the version is out and the workflow
refuses to release it again, so finish by hand what the failed run left. For the server SDK, with the commit the
run released, which its page on GitHub names, and the version's changelog section saved to a file:

```sh
git tag -a configdirector-server-sdk-vX.Y.Z <released commit> -m 'configdirector-server-sdk X.Y.Z'
git push origin configdirector-server-sdk-vX.Y.Z
gh release create configdirector-server-sdk-vX.Y.Z --repo ConfigDirector/ruby-sdks --verify-tag \
  --title configdirector-server-sdk-vX.Y.Z --notes-file <file with the changelog section>
```

The three workflow files are the same file with another gem's name, and they share no reusable workflow: RubyGems
trusts a workflow file to publish a gem, so each file can publish its own gem and no other. To change the release
steps, edit [release-configdirector-server-sdk.yml](.github/workflows/release-configdirector-server-sdk.yml) and
write the other two again from it:

```sh
cd .github/workflows
for gem in configdirector-openfeature-server-provider configdirector; do
  sed "s/configdirector-server-sdk/$gem/g" release-configdirector-server-sdk.yml > "release-$gem.yml"
done
```

The refusals live in [release-preflight.sh](.github/scripts/release-preflight.sh), the check of a built gem in
[verify-built-gem.rb](tools/verify-built-gem.rb) and the push in [publish-gem.rb](.github/scripts/publish-gem.rb).
`make test-release` runs all three one scenario at a time, with throwaway git repositories and a local server
standing in for RubyGems and for GitHub, and fails when the three workflow files differ by more than the gem's
name.

### What a release publishes

A gem ships what an application needs and nothing else: `lib/**/*.rb`, `sig/**/*.rbs`, `.yardopts`, `CHANGELOG.md`,
`LICENSE` and `README.md`, which is what the `files` of each gemspec list. `make build` fails on a built gem that
holds anything else, such as a spec, a sample or a `Gemfile`; that lacks `README.md`, `CHANGELOG.md` or `LICENSE`;
that holds Ruby code without its signatures; or that does not set `rubygems_mfa_required`, which makes RubyGems
require multi-factor authentication of every owner who pushes or yanks the gem with their own account. So a new
file that an application needs goes into the gemspec and into [verify-built-gem.rb](tools/verify-built-gem.rb).
The `LICENSE` of each gem is a copy of the one at the root, because a gem packs only files of its own directory.

### How the workflow signs in to RubyGems

No RubyGems credential is stored in GitHub. RubyGems lets a gem name a **trusted publisher**: a GitHub repository,
a workflow file in it and an environment. The publish job of each workflow is the only job in the `release`
environment and the only one that may ask GitHub for an identity token. `publish-gem.rb` hands that token to
RubyGems, which checks that it comes from the trusted publisher and answers with a key that can push that gem
alone and expires within minutes. The key stays inside the script.

Renaming a release workflow file or the `release` environment means changing the gem's trusted publisher on
RubyGems first, on the gem's page under **Trusted publishers**.

The script exchanges the token itself rather than through `rubygems/configure-rubygems-credentials`. Since
2026-10-30 RubyGems lets a workflow create a new gem only when the exchange names the account that will own it,
and that action (v2.1.0) has no way to name one. The script names the account on every exchange, from the
`RUBYGEMS_OWNER_ID` variable of the `release` environment, so the first push of a gem and every later one take
the same path.

### Setting up RubyGems and GitHub

Steps 1 to 3 are done once, by the person whose RubyGems account owns the gems and who administers this
repository. Step 4 is done once per gem, on the day of its first release. Each step ends with a command that
changes nothing and proves it.

**1. Turn on multi-factor authentication for the RubyGems account that owns the gems.** Sign in to
<https://rubygems.org> as that account and open <https://rubygems.org/settings/edit>, the **Edit settings** page.
In its **Multi-factor authentication** section:

| On the page | What to do | What it is for, and what goes wrong otherwise |
|---|---|---|
| **Security device**, or **Authentication app** with **Register a new device** | Register a device, when the account has none | An account without a device has no multi-factor authentication at all. |
| **MFA Level** | Choose **UI and API (Recommended)** and click **Update** | Every gem here sets `rubygems_mfa_required`, which makes RubyGems require multi-factor authentication of the gem's owners. The release workflow is not asked for a code, so it publishes either way; what fails on an account without it is a `gem push` made by hand with the account's own key, which RubyGems refuses with `Rubygem requires owners to enable MFA. You must enable MFA before pushing new version.` |

Prove it, with the account's username in `HANDLE`. curl asks for the account's password and sends it to RubyGems
alone. The answer has to hold `"mfa":"ui_and_api"`, and its `id` is the account ID that step 2 needs.

```sh
HANDLE=<username>
curl --silent --user "$HANDLE" https://rubygems.org/api/v1/profile/me.json
```

**2. Create the `release` environment in this repository.** On GitHub, open this repository's **Settings**, click
**Environments** in the left sidebar, then **New environment**:

| On the page | Value | What it is for, and what goes wrong otherwise |
|---|---|---|
| **Name** | `release`, then **Configure environment** | The environment the publish job runs in and RubyGems trusts. Under another name, GitHub creates an empty `release` environment by itself when the workflow first runs, so the job starts without the variable below and stops with `RUBYGEMS_OWNER_ID is ''`. |
| **Deployment branches and tags** | **Selected branches and tags**, with one rule for the branch `main` | Only a run against `main` may enter the environment. With **No restriction**, a workflow file changed on any branch of this repository could publish a gem. With a rule that does not match `main`, GitHub refuses the publish job before it starts. |
| **Environment variables**, **Add variable** | **Name** `RUBYGEMS_OWNER_ID`, **Value** the `id` that step 1 printed | Tells RubyGems which account will own a gem this workflow creates. A handle or an empty value stops the publish job with `RUBYGEMS_OWNER_ID is '...'` before it asks RubyGems for anything, and the ID of another account makes the first push of a gem fail with `You are not allowed to push this gem.` |

Prove it: the first command has to print `release`, the second `main`, and the third `RUBYGEMS_OWNER_ID` followed
by the ID.

```sh
gh api repos/ConfigDirector/ruby-sdks/environments --jq '.environments[].name'
gh api repos/ConfigDirector/ruby-sdks/environments/release/deployment-branch-policies --jq '.branch_policies[].name'
gh api repos/ConfigDirector/ruby-sdks/environments/release/variables --jq '.variables[] | "\(.name) \(.value)"'
```

**3. Check that nobody holds the gem names.** RubyGems gives a name to the first account that pushes it. Each line
has to end with `404` until the gem's first release.

```sh
for gem in configdirector-server-sdk configdirector-openfeature-server-provider configdirector; do
  curl --silent --output /dev/null --write-out "$gem %{http_code}\n" "https://rubygems.org/api/v1/gems/$gem.json"
done
```

**4. Create a pending trusted publisher for the gem, on the day of its first release.** A gem that does not exist
yet has no page to add a trusted publisher on, so the account that will own it registers a pending one, which
RubyGems keeps for 12 hours: create it, run the workflow with **dry_run**, and run it again without, all within
that time. Signed in as the owning account, open <https://rubygems.org/profile/oidc/pending_trusted_publishers>,
the **Pending Trusted Publishers** page, click **Create**, and fill in **New Pending Trusted Publisher**. For the
server SDK:

| Field on the page | Value | What it is for, and what goes wrong otherwise |
|---|---|---|
| **RubyGem name** | `configdirector-server-sdk` | The gem the first push creates. Under another name the push fails with `You are not allowed to push this gem.` |
| **Trusted publisher type** | **GitHub Actions** | The kind of publisher these workflows are. Under another type RubyGems finds no publisher for the workflow's token, and the exchange fails with HTTP 404. |
| **Repository owner** | `ConfigDirector` | With **Repository name**, the repository whose workflow RubyGems trusts. |
| **Repository name** | `ruby-sdks` | A wrong owner or name makes the exchange fail in the publish job with HTTP 404. |
| **Workflow filename** | `release-configdirector-server-sdk.yml` | The file name alone, without `.github/workflows/`. Each gem has its own: `release-<gem>.yml`. A wrong name makes the exchange fail with HTTP 404. |
| **Environment** | `release` | The environment of step 2. Another name makes the exchange fail with HTTP 404. Left blank, any job of that workflow file could publish, in any environment. |
| **Workflow Repository Owner** | Leave blank | Only for a reusable workflow kept in another repository, which these are not. Filled in with this repository, the form is refused with `workflow_repository must be different from the repository, leave blank for same-repository workflows`; with another one, the exchange fails with HTTP 404. |
| **Workflow Repository Name** | Leave blank | The same as the row above. |

Then click **Create Pending trusted publisher**. The page lists the publisher with **Valid for** and the time it
has left, and a line that says the workflow must pass `owner:` with a number: that number has to be the
`RUBYGEMS_OWNER_ID` of step 2.

Prove it before anything is published: run the gem's release workflow against `main` with **dry_run** checked.
Its publish job has to end with a line such as the one below, naming the workflow file, the environment and the
username of the owning account, followed by `Dry run:` and the gem file it did not push.

```
RubyGems trusts this workflow as 'GitHub Actions ConfigDirector/ruby-sdks @ .github/workflows/release-configdirector-server-sdk.yml (release) ...', and reads the owner 123456 as the account '<username>'.
```

The dry run proves the repository, the workflow file name, the environment and the account ID. It cannot prove
the gem name or that the pending publisher has time left, which the page shows. After the first push RubyGems
turns the pending publisher into the gem's own, makes the account the gem's owner, and lists the publisher on the
gem's page under **Trusted publishers**; later releases need none of step 4. Prove the first release with:

```sh
GEM=configdirector-server-sdk
curl --silent "https://rubygems.org/api/v1/gems/$GEM/owners.json"
curl --silent "https://rubygems.org/api/v1/versions/$GEM.json" | jq '.[] | {number, metadata}'
gh release view "$GEM-vX.Y.Z" --repo ConfigDirector/ruby-sdks
```

The first has to name the owning account alone, the second the version with `rubygems_mfa_required` in its
metadata, and the third the GitHub Release on the tag.

### When RubyGems refuses the workflow

The publish job prints RubyGems' answer. What each one means:

| Answer | Cause |
|---|---|
| `RubyGems did not exchange the identity token of this job for a key (HTTP 404)` | RubyGems knows no trusted publisher with this repository, this workflow file name and the `release` environment: the pending publisher of step 4 was never created or has a field that differs, or, for a gem that exists, its **Trusted publishers** page does not list this workflow. |
| `RubyGems did not exchange the identity token of this job for a key (HTTP 400): {"error":"Unknown owner ..."}` | `RUBYGEMS_OWNER_ID` is not the ID of a RubyGems account. |
| `You are not allowed to push this gem.` after `Pushing gem to https://rubygems.org...` | The exchange worked and the push was refused: the account that `RUBYGEMS_OWNER_ID` names has no pending trusted publisher for this gem name with time left, or the gem exists and this workflow is not among its trusted publishers. |
| `GitHub did not give this job an identity token` or `This job may not request an identity token from GitHub` | The publish job lost its `id-token: write` permission. |

### Version line

The gems stay at `0.x` until the SDK functional tests pass against them in dev, which is when `1.0.0` is
released.
