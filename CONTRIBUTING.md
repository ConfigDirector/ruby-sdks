# Contributing

## The gems

This repository publishes three gems, each from a directory named after it, with its own version, changelog and
release.

| Gem | What it is | Ruby | Loaded with |
|---|---|---|---|
| [configdirector-server-sdk](configdirector-server-sdk/) | The server SDK, module `ConfigDirector` | 3.3 or later | `require "configdirector"` |
| [configdirector-openfeature-server-provider](configdirector-openfeature-server-provider/) | The OpenFeature provider built on the SDK, module `ConfigDirector::OpenFeature` | 3.4 or later | `require "configdirector/openfeature"` |
| [configdirector](configdirector/) | Holds the bare name on RubyGems. It has no code and depends on the SDK, so installing it installs the SDK | 3.3 or later | `require "configdirector"`, which is the SDK's |

[samples/](samples/) holds sample applications and [profiling/](profiling/) holds measurements of the SDK. Each
has its own README.

Rules to keep:

- **`configdirector` never ships a `lib/configdirector.rb`.** It would be loaded in place of the SDK's.
- **The SDK depends on Ruby's standard library only.** Its gemspec names `logger`, which Bundler no longer loads
  on its own on Ruby 4.0, and `net-http` 0.10.0 or later, the first release that limits the head of an answer and
  each chunk size line to 1 MiB.
- **The provider develops against the SDK in this working tree**, which its `Gemfile` names by path. Its gemspec
  accepts the SDK from `0.1.0` and below `1`.
- **Lock files are committed.** Run `make install` after a change to a `Gemfile` or gemspec. A gem's lock has to
  keep `x64-mingw-ucrt` under `PLATFORMS`, so that Windows runners install prebuilt native gems. Add it back with
  `bundle lock --add-platform x64-mingw-ucrt`.
- **A gemspec reads its version from the text of `version.rb`** and never requires the file. Bundler loads a
  gemspec before the gem, so requiring it would define the gem's module too early.
- **Each gem ships a file named after the gem**, such as `lib/configdirector-server-sdk.rb`, because
  `Bundler.require` loads a gem by its gem name.
- **A sample is its own Bundler project** and installs into its own `vendor/bundle`. Its `Gemfile` names a
  released version of the gem it shows, the way an application does. CI runs the samples on Ubuntu only, and on
  Windows the Makefile targets take `SAMPLES=`.

## Working on the gems

You need Ruby 3.4 or later, Bundler, and Docker for `make check-floor`. Ruby has to be 3.3.13, 3.4.12, 4.0.9 or a
later release on the same line, which have the regular expression fixes of 2026-10-23: `make verify-ruby` fails on
an older one. On macOS, `brew install ruby` and put `/opt/homebrew/opt/ruby/bin` in front of the system Ruby on
your `PATH`.

| Command | What it runs |
|---|---|
| `make install` | `bundle install` for every gem and sample |
| `make hooks` | Installs the pre-push hook, which runs `make check-all` |
| `make check` | Lint and tests: the fast loop |
| `make format` | RuboCop's safe corrections |
| `make test-lowest` | The suites with each runtime dependency at the lowest version the gemspec allows |
| `make test-release` | The release scripts, against throwaway repositories and a stand-in for RubyGems |
| `make samples` | The samples' suites against the released gems their locks name |
| `make samples-local` | The same suites against the gems in this working tree |
| `make build` | Builds each gem into `dist/` and checks [what it holds](#what-a-gem-ships) |
| `make audit` | `bundle-audit` against each lock |
| `make check-floor` | Lint and tests on each gem's oldest Ruby line, in Docker |
| `make check-all` | Everything above that is a check |
| `make profile` | A measurement, not a check: see [profiling/README.md](profiling/README.md) |

- **One gem:** `make test GEMS=configdirector-server-sdk`. **Without the samples:** add `SAMPLES=`.
- **New checks go in the [Makefile](Makefile).** CI and the pre-push hook only call `make` targets.
- **CI covers more than `make check-all`.** It runs the SDK's suite on Ubuntu (Ruby 3.3, 3.4 and 4.0), macOS
  (4.0) and Windows (3.3 and 4.0), the provider's on Ubuntu (3.4 and 4.0) and the samples' on Ubuntu (3.3 and
  4.0). `make check-all` covers your own Ruby and each gem's oldest Ruby line.

### Lint and types

- **A finding is fixed, not ignored.** No file under `lib` is excluded from RuboCop and no line disables a cop.
- **RSpec fails a run** on a Ruby warning, an RSpec warning or deprecation, and an example left focused, skipped
  or pending.
- **Steep checks the code against the RBS signatures in `sig/`**, which ship in the gem.
- **YARD comments document the public API only.** `ConfigDirector::Internal` is tagged `@api private`, so
  rubydoc.info leaves it out.
- **The SDK's `.rubocop.yml` sets three cops apart:** `Style/Documentation` checks the public API's files only,
  `Naming/FileName` accepts the file named after the gem, and `Lint/InheritException` is off because
  `StoppableThread::Stopped` must not be caught by `rescue => e`.
- **`spec/signature_fixture/` holds type errors on purpose.** Each says which type the checker sees for a read,
  and `steep_expectations.yml` lists them. After a change to the fixture or a Steep release, run
  `bundle exec steep check --save-expectations=spec/signature_fixture/steep_expectations.yml` in the SDK's
  directory and read the diff.
- **`sig_missing_from_rbs/` holds signatures of Ruby's own classes that the released `rbs` gem lacks.** The gem
  does not ship it. Delete a file there once an `rbs` release has its signature.
- **The provider's `sig_missing_from_openfeature_sdk/` holds the `new` of `openfeature-sdk`'s keyword structs**,
  which the signatures `openfeature-sdk` ships lack. The gem does not ship it either.

### Specs

- **No spec stubs `net/http`.** A spec that needs an SDK server starts `spec/support/scripted_sdk_server.rb`, a
  real server on a local port that the example scripts. It accepts telemetry reports by itself unless the example
  calls `hold_telemetry_reports`. The provider's specs start the same server, through
  `configdirector-openfeature-server-provider/spec/support/provider_over_the_scripted_sdk_server.rb`.
- **The provider's `spec_helper.rb` loads `openfeature-sdk` before Ruby warnings fail the run.** `openfeature-sdk`
  0.8.1 requires its own files in a circle, and Ruby warns about it once, when the gem loads.
- **Every new regular expression gets an example** in `spec/configdirector/internal/regular_expressions_spec.rb`,
  which gives each one 100,000 characters written to make it backtrack and one second to answer.
- **A handler that forks in an example forks once.** The forked process runs the same handler again, so set a
  flag before the `fork`.
- **An example that needs to know how far the SDK read an answer sends it in pieces.** Windows takes one large
  write whole.
- **The SDK cannot be made to trust a local certificate.** `spec/support/self_signed_tls_listener.rb` serves the
  examples that assert the SDK ends the handshake. The one example that needs a trusted TLS stream starts a
  process of its own with `SSL_CERT_FILE` set.
- **Examples that do not run everywhere:**

  | Example | Runs on | Why |
  |---|---|---|
  | A client in a forked process | Ubuntu and macOS | Windows cannot fork |
  | Garbage collection of a closed client | Ruby 4.0 and later | The `timeout` library of Ruby 3.3 and 3.4 keeps the client reachable |
  | Connecting to an address that never answers | Ubuntu and macOS | Nothing can end a connection attempt on Windows before Windows gives up |

## How the provider identifies itself

The SDK reports its name and version, `ruby-server-sdk` and `ConfigDirector::VERSION`, in the `User-Agent` header
and in the `metaContext` of its requests. A gem built on the SDK reports its own name and version instead, through
a closed list that the SDK keeps, `ConfigDirector::Internal::Identity::Wrapper`. The list is not public API. Its
one entry creates a client that reports the provider:

```ruby
ConfigDirector::Internal::Identity::Wrapper::OPENFEATURE_SERVER_PROVIDER.create_client(server_sdk_key, logger: logger)
```

Adding a wrapper gem means adding it to that list, releasing the SDK, and registering the new name in the
ConfigDirector capability tables.

## Releasing

Each gem is released on its own, by running its workflow by hand. A gem's version lives in one place:

| Gem | Version | Changelog | Workflow |
|---|---|---|---|
| configdirector-server-sdk | `VERSION` in [`version.rb`](configdirector-server-sdk/lib/configdirector/version.rb) | [CHANGELOG.md](configdirector-server-sdk/CHANGELOG.md) | [Release configdirector-server-sdk](.github/workflows/release-configdirector-server-sdk.yml) |
| configdirector-openfeature-server-provider | `VERSION` in [`version.rb`](configdirector-openfeature-server-provider/lib/configdirector/openfeature/version.rb) | [CHANGELOG.md](configdirector-openfeature-server-provider/CHANGELOG.md) | [Release configdirector-openfeature-server-provider](.github/workflows/release-configdirector-openfeature-server-provider.yml) |
| configdirector | `spec.version` in [`configdirector.gemspec`](configdirector/configdirector.gemspec) | [CHANGELOG.md](configdirector/CHANGELOG.md) | [Release configdirector](.github/workflows/release-configdirector.yml) |

### Release a gem

1. **Changelog.** Rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and open an empty `## [Unreleased]` above
   it.
2. **Version.** Set it to `X.Y.Z`, run `make install` to update the lock files, and merge to `main`.
3. **Dry run.** Run the gem's workflow against `main` with **dry_run** checked. It runs every check, has RubyGems
   accept the workflow, and publishes nothing. Needed before a gem's first release, and after a change to the
   publish job or the gem's trusted publisher.
4. **Release.** Run the gem's workflow against `main`.
5. **Samples.** In each of the gem's samples, run `bundle update <gem>` and merge its `Gemfile.lock`, so the
   sample installs the new version.

> [!IMPORTANT]
> A gem's first release also needs a pending trusted publisher, created on RubyGems the same day:
> [step 4 of the one-time setup](#4-pending-trusted-publisher-on-the-day-of-a-gems-first-release).

The workflow:

1. Refuses to go on when it is not run against `main`, the version is not `X.Y.Z`, the tag `<gem>-vX.Y.Z` exists,
   RubyGems already has the version, or the changelog has no section for it or an empty one.
2. Installs the built gem with its dependencies from RubyGems alone and loads it (`make release-check`), then
   runs `make check-all`.
3. Builds the gem on a fresh checkout and checks what it holds.
4. Pushes the gem to RubyGems.
5. Tags the commit `<gem>-vX.Y.Z` and creates a GitHub Release with the changelog section as its notes.

Rules to keep:

- **A version is `X.Y.Z`.** The workflow releases no prerelease. RubyGems never accepts a version twice, a yanked
  one included: to ship a fix, raise the version and release again.
- **Release the SDK first.** The workflows of the provider and of `configdirector` stop at `make release-check`
  until RubyGems serves an SDK version in the range their gemspec names.
- **`configdirector` is released again only when its range of SDK versions changes**, at the SDK's `1.0.0`.
- **An unreleased gem is at `0.1.0-dev`**, never `0.0.0-dev`, which a `Gemfile` that names the gem by its path
  does not resolve.
- **The gems stay at `0.x`** until the SDK functional tests pass against them in dev, which is when `1.0.0` is
  released.

### When a release fails

- **Before the push to RubyGems:** nothing is published. Fix the cause and run the workflow again.
- **After the push**, when the tag or the GitHub Release failed: the version is out, and the workflow refuses to
  release it again. Finish by hand, with the commit the run released and the changelog section saved to a file:

  ```sh
  git tag -a configdirector-server-sdk-vX.Y.Z <released commit> -m 'configdirector-server-sdk X.Y.Z'
  git push origin configdirector-server-sdk-vX.Y.Z
  gh release create configdirector-server-sdk-vX.Y.Z --repo ConfigDirector/ruby-sdks --verify-tag \
    --title configdirector-server-sdk-vX.Y.Z --notes-file <file with the changelog section>
  ```

### When RubyGems refuses the workflow

The publish job prints RubyGems' answer:

| The job prints | Cause |
|---|---|
| `RubyGems did not exchange the identity token of this job for a key (HTTP 404)` | RubyGems knows no trusted publisher with this repository and this workflow file name. The pending publisher was never created, has a field that differs or names an environment, or the gem exists and its **Trusted publishers** page does not list this workflow. |
| `... (HTTP 400): {"error":"Unknown owner ..."}` | `RUBYGEMS_OWNER_ID` is not the ID of a RubyGems account. |
| `You are not allowed to push this gem.` | The exchange worked and the push was refused. The account that `RUBYGEMS_OWNER_ID` names has no pending trusted publisher for this gem name with time left, or the gem exists and this workflow is not among its trusted publishers. |
| `GitHub did not give this job an identity token` or `This job may not request an identity token from GitHub` | The publish job lost its `id-token: write` permission. |

### What a gem ships

A gem ships `lib/**/*.rb`, `sig/**/*.rbs`, `.yardopts`, `CHANGELOG.md`, `LICENSE` and `README.md`, and nothing
else. `make build` fails on a built gem that holds another file, such as a spec or a `Gemfile`, that lacks one of
those three documents or the signatures of its code, or that does not set `rubygems_mfa_required`. A new kind of
file that an application needs goes into the gemspec and into [verify-built-gem.rb](tools/verify-built-gem.rb).
Each gem's `LICENSE` is a copy of the one at the root.

### Changing the release workflows

- **The three workflow files are one text with another gem's name.** Edit
  [release-configdirector-server-sdk.yml](.github/workflows/release-configdirector-server-sdk.yml) and write the
  other two again from it. `make test-release` fails when they differ by more than the name.

  ```sh
  cd .github/workflows
  for gem in configdirector-openfeature-server-provider configdirector; do
    sed "s/configdirector-server-sdk/$gem/g" release-configdirector-server-sdk.yml > "release-$gem.yml"
  done
  ```

- **They share no reusable workflow.** RubyGems trusts a workflow file to publish a gem, so each file can publish
  its own gem and no other.
- **No RubyGems credential is stored in GitHub.** The publish job hands its GitHub identity token to RubyGems,
  which answers with a key that can push that gem alone and expires within minutes.
- **Write access to this repository is the permission to release.** The publish job runs in no GitHub
  environment, so RubyGems trusts the workflow file on any branch, and the refusal of a branch other than `main`
  is a step of that file.
- **The exchange is our own script**, [publish-gem.rb](.github/scripts/publish-gem.rb), not
  `rubygems/configure-rubygems-credentials`. Since 2026-10-30 RubyGems lets a workflow create a new gem only when
  the exchange names the account that will own it, which that action (v2.1.0) cannot do. The script names it from
  the repository variable `RUBYGEMS_OWNER_ID`.
- **Before renaming a workflow file**, change the gem's trusted publisher on RubyGems, on the gem's page under
  **Trusted publishers**.
- **The scripts:** the refusals are in [release-preflight.sh](.github/scripts/release-preflight.sh), the check of
  a built gem in [verify-built-gem.rb](tools/verify-built-gem.rb) and the push in
  [publish-gem.rb](.github/scripts/publish-gem.rb). `make test-release` runs all three.

### One-time setup

Steps 1 to 3 are done once, by the person whose RubyGems account owns the gems and who administers this
repository. Step 4 is done once per gem. Each step ends with a command that changes nothing and proves it.

#### 1. Multi-factor authentication on the RubyGems account

Signed in to RubyGems, open <https://rubygems.org/settings/edit>, the **Edit settings** page, and find the
**Multi-factor authentication** section.

| On the page | What to do | What it is for, and what goes wrong otherwise |
|---|---|---|
| **Security device** or **Authentication app** | Register a device | An account without a device has no multi-factor authentication at all. |
| **MFA Level** | **UI and API (Recommended)**, then **Update** | Every gem here requires it of its owners. The release workflow is not asked for a code, so it publishes either way. A `gem push` or `gem yank` by hand is refused without it: `Rubygem requires owners to enable MFA. You must enable MFA before pushing new version.` |

Prove it. curl asks for the account's password and sends it to RubyGems alone. The answer has to hold
`"mfa":"ui_and_api"`, and its `id` is the account ID that step 2 needs.

```sh
curl --silent --user <username> https://rubygems.org/api/v1/profile/me.json
```

#### 2. The `RUBYGEMS_OWNER_ID` variable on GitHub

The release workflows tell RubyGems which account will own a gem they create. Set the variable to the `id` from
step 1:

```sh
gh variable set RUBYGEMS_OWNER_ID --repo ConfigDirector/ruby-sdks --body <id from step 1>
```

On GitHub the same is **Settings**, **Secrets and variables**, **Actions**, the **Variables** tab, then
**New repository variable** with **Name** `RUBYGEMS_OWNER_ID` and **Value** the ID.

A username or an empty value stops the publish job with `RUBYGEMS_OWNER_ID is '...'`. Another account's ID makes a
gem's first push fail with `You are not allowed to push this gem.`

Prove it. The command has to print the ID.

```sh
gh variable get RUBYGEMS_OWNER_ID --repo ConfigDirector/ruby-sdks
```

#### 3. The gem names are free

RubyGems gives a name to the first account that pushes it. Each line has to end with `404` until the gem's first
release.

```sh
for gem in configdirector-server-sdk configdirector-openfeature-server-provider configdirector; do
  curl --silent --output /dev/null --write-out "$gem %{http_code}\n" "https://rubygems.org/api/v1/gems/$gem.json"
done
```

#### 4. Pending trusted publisher, on the day of a gem's first release

> [!IMPORTANT]
> RubyGems keeps a pending trusted publisher for 12 hours. Create it, do the dry run and release within that time.

Signed in as the owning account, open <https://rubygems.org/profile/oidc/pending_trusted_publishers>, click
**Create**, and fill in **New Pending Trusted Publisher**. For the server SDK:

| Field | Value | What it is for, and what goes wrong otherwise |
|---|---|---|
| **RubyGem name** | `configdirector-server-sdk` | The gem the first push creates. Under another name the push fails with `You are not allowed to push this gem.` |
| **Trusted publisher type** | **GitHub Actions** | Under another type the exchange fails with HTTP 404. |
| **Repository owner** | `ConfigDirector` | The repository whose workflow RubyGems trusts. A wrong owner makes the exchange fail with HTTP 404. |
| **Repository name** | `ruby-sdks` | The same: a wrong name makes the exchange fail with HTTP 404. |
| **Workflow filename** | `release-configdirector-server-sdk.yml` | The file name alone, without `.github/workflows/`. Each gem has its own, `release-<gem>.yml`. A wrong name makes the exchange fail with HTTP 404. |
| **Environment** | Leave blank | The publish job runs in no GitHub environment. With a name here, the exchange fails with HTTP 404. |
| **Workflow Repository Owner** | Leave blank | Only for a reusable workflow kept in another repository. Filled in with this repository, the form is refused with `workflow_repository must be different from the repository`; with another one, the exchange fails with HTTP 404. |
| **Workflow Repository Name** | Leave blank | The same as the row above. |

Then click **Create Pending trusted publisher**.

Prove it with the dry run of [Release a gem](#release-a-gem). Its publish job has to end with this line, naming
the workflow file and the username of the owning account:

```
RubyGems trusts this workflow as 'GitHub Actions ConfigDirector/ruby-sdks @ .github/workflows/release-configdirector-server-sdk.yml ...', and reads the owner 123456 as the account '<username>'.
```

The dry run cannot prove the gem name or the time the pending publisher has left. The page shows both.

After the release, the first command has to name the owning account alone, the second the version with
`rubygems_mfa_required` in its metadata, and the third the GitHub Release on the tag.

```sh
GEM=configdirector-server-sdk
curl --silent "https://rubygems.org/api/v1/gems/$GEM/owners.json"
curl --silent "https://rubygems.org/api/v1/versions/$GEM.json" | jq '.[] | {number, metadata}'
gh release view "$GEM-vX.Y.Z" --repo ConfigDirector/ruby-sdks
```

Later releases of the gem need none of step 4: RubyGems turns the pending publisher into the gem's own at the
first push.
