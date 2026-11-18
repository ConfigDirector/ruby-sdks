.PHONY: install hooks verify-ruby verify-lock format lint _lint test test-lowest test-release samples samples-local \
	build release-check audit check-floor _check-floor check check-all clean profile profile-fork-per-job

# Every gem with code that this repository publishes, each in a directory named after it. Narrow a target to one of
# them with, for example, `make test GEMS=configdirector-server-sdk`.
SDK := configdirector-server-sdk
PROVIDER := configdirector-openfeature-server-provider
GEMS := $(SDK) $(PROVIDER)

# The gem that holds the bare name `configdirector` on RubyGems. It has no code, only a dependency on the SDK, so it
# has nothing to install, lint or test, and `build` and the release checks are the only targets that know it.
BARE_NAME_GEM := configdirector
PUBLISHED_GEMS := $(GEMS) $(BARE_NAME_GEM)

# Sample applications, each a Bundler project under samples/<gem>/<framework> that names a released version of the
# gem it shows, the way an application does. `install`, `verify-lock`, `format`, `lint`, `audit` and `clean` run on
# each sample as well as on each gem; `SAMPLES=` leaves the samples out.
SAMPLES := samples/configdirector-server-sdk/rails samples/configdirector-openfeature-server-provider/sinatra

PROJECTS := $(GEMS) $(SAMPLES)

# The official image of each gem's oldest supported Ruby line. `check-floor` runs the gem's lint and suite in it.
FLOOR_IMAGE_$(SDK) := ruby:3.3
FLOOR_IMAGE_$(PROVIDER) := ruby:3.4

# The options `lint` gives Steep in each gem. The SDK's Steepfile also checks its signature fixture, code that reads
# values the way an application would, whose type errors are deliberate and listed in its expectations file.
STEEP_OPTIONS_$(SDK) := --with-expectations=spec/signature_fixture/steep_expectations.yml
STEEP_OPTIONS_$(PROVIDER) :=

# Ruby code outside a gem's directory that the gem's RuboCop checks with it: the measurements under profiling/ run on
# the SDK, with its bundle.
ALSO_LINTED_WITH_$(SDK) := ../profiling
ALSO_LINTED_WITH_$(PROVIDER) :=

install:
	@for project in $(PROJECTS); do \
		printf '\n\033[1m==> install %s\033[0m\n' "$$project"; \
		(cd "$$project" && bundle install --quiet) || exit 1; \
	done

hooks:
	git config core.hooksPath .githooks
	@echo "pre-push hook installed. Bypass a single push with 'git push --no-verify'."

# Fails on a Ruby release without the regular expression fixes that tools/verify-ruby.rb lists, and prints the
# running Ruby version either way.
verify-ruby:
	@printf '\n\033[1m==> verify-ruby\033[0m\n'
	@ruby tools/verify-ruby.rb

# Asserts each Gemfile.lock is still consistent with its Gemfile and gemspec, which is what CI installs from.
verify-lock:
	@for project in $(PROJECTS); do \
		printf '\n\033[1m==> verify-lock %s\033[0m\n' "$$project"; \
		(cd "$$project" && BUNDLE_FROZEN=true bundle install --quiet) || exit 1; \
	done

format: install
	@for project in $(PROJECTS); do \
		(cd "$$project" && bundle exec rubocop --autocorrect) || exit 1; \
	done

lint: install
	@for gem in $(GEMS); do \
		$(MAKE) --no-print-directory _lint GEM="$$gem" || exit 1; \
	done
	@for sample in $(SAMPLES); do \
		printf '\n\033[1m==> lint %s\033[0m\n' "$$sample"; \
		(cd "$$sample" && bundle exec rubocop) || exit 1; \
	done

_lint:
	@printf '\n\033[1m==> lint %s\033[0m\n' "$(GEM)"
	@cd "$(GEM)" && bundle exec rubocop . $(ALSO_LINTED_WITH_$(GEM)) && bundle exec steep check $(STEEP_OPTIONS_$(GEM))

test: install
	@for gem in $(GEMS); do \
		printf '\n\033[1m==> test %s\033[0m\n' "$$gem"; \
		(cd "$$gem" && bundle exec rspec) || exit 1; \
	done

# The same suites against the lowest version of each runtime dependency that the gemspec allows. Without this a
# floor such as `logger ~> 1.6` is only ever a guess, because the lock picks the newest. A dependency on another gem
# of this repository stays the one in this working tree, which the gem's Gemfile names by its path. Bundler resolves
# into a throwaway Gemfile and lock, so the committed lock stays as it is.
test-lowest:
	@for gem in $(GEMS); do \
		printf '\n\033[1m==> test-lowest %s\033[0m\n' "$$gem"; \
		lowest=$$(mktemp -d); \
		ruby tools/lowest-dependencies-gemfile.rb "$$gem" > "$$lowest/Gemfile" \
			&& (cd "$$gem" \
				&& BUNDLE_GEMFILE="$$lowest/Gemfile" bundle install --quiet \
				&& BUNDLE_GEMFILE="$$lowest/Gemfile" bundle exec rspec); \
		status=$$?; rm -rf "$$lowest"; [ "$$status" -eq 0 ] || exit "$$status"; \
	done

# The release workflows' scripts decide the version, the tag and the notes of a release, refuse one they must not
# make, check what a built gem holds and push it to RubyGems. This runs them one scenario at a time, with throwaway
# git repositories and a local server standing in for RubyGems and for GitHub, and checks that the three release
# workflows differ by the gem's name alone.
test-release:
	@printf '\n\033[1m==> test-release\033[0m\n'
	.github/scripts/release-test.sh

# The suite of each sample against the released gem its Gemfile.lock names, the way an application installs it. Each
# sample installs its own bundle, so a Ruby line that one of the gems does not support, such as 3.3 for the provider,
# can still run the samples of the other.
samples:
	@for sample in $(SAMPLES); do \
		printf '\n\033[1m==> samples %s (released gem)\033[0m\n' "$$sample"; \
		(cd "$$sample" && bundle install --quiet && bundle exec rspec) || exit 1; \
	done

# The same suites against the gems in this working tree, which is what catches a change to a gem that breaks the
# code an application writes against it; `samples` cannot, because a sample's lock names a release. Each sample is
# copied to a throwaway directory, where the Gemfile line of each gem of this repository names the gem's directory
# here, so the sample's own Gemfile and Gemfile.lock stay as they are. The copy uses the gems already installed in
# the sample's vendor/bundle.
samples-local:
	@for sample in $(SAMPLES); do \
		printf '\n\033[1m==> samples-local %s (working-tree gems)\033[0m\n' "$$sample"; \
		copy=$$(mktemp -d); \
		tar -C "$$sample" --exclude=./vendor --exclude=./.bundle --exclude=./log --exclude=./tmp --exclude=./.env \
			-cf - . | tar -C "$$copy" -xf - \
		&& sed -E -i.released 's|^gem "(configdirector[^"]*)".*|gem "\1", path: "$(CURDIR)/\1"|' "$$copy/Gemfile" \
		&& (cd "$$copy" \
			&& BUNDLE_PATH="$(CURDIR)/$$sample/vendor/bundle" bundle install --quiet \
			&& BUNDLE_PATH="$(CURDIR)/$$sample/vendor/bundle" bundle exec rspec); \
		status=$$?; rm -rf "$$copy"; [ "$$status" -eq 0 ] || exit "$$status"; \
	done

# One .gem file per published gem under dist/. --strict turns every warning about the gemspec into a failure, and
# tools/verify-built-gem.rb fails on a built gem that holds a file an application does not need, such as a spec or
# a Gemfile, that lacks its signatures, README.md, CHANGELOG.md or LICENSE, or whose owners RubyGems would not
# require multi-factor authentication of.
build:
	@rm -rf dist
	@mkdir dist
	@for gem in $(PUBLISHED_GEMS); do \
		printf '\n\033[1m==> build %s\033[0m\n' "$$gem"; \
		(cd "$$gem" && gem build --strict --quiet "$$gem.gemspec" && mv "$$gem"-*.gem ../dist/) || exit 1; \
	done
	@ruby tools/verify-built-gem.rb dist/*.gem
	@ls dist

# What an application gets from a release of $(GEM): the built gem installed into an empty gem home, with its
# dependencies taken from RubyGems, which serves neither this working tree nor a version of another gem of this
# repository that is not released yet, and then loaded by the name `Bundler.require` uses. A release workflow runs
# this before it publishes. It is not part of check-all: it fails, as it should, for a gem that depends on a version
# of another gem here that RubyGems does not have yet.
release-check: build
	@test -n "$(GEM)" || { echo "usage: make release-check GEM=<gem>"; exit 2; }
	@printf '\n\033[1m==> release-check %s\033[0m\n' "$(GEM)"
	@gem_home=$$(mktemp -d); \
		GEM_HOME="$$gem_home" GEM_PATH="$$gem_home" gem install --no-document dist/$(GEM)-[0-9]*.gem \
			&& GEM_HOME="$$gem_home" GEM_PATH="$$gem_home" ruby -e 'gem ARGV.fetch(0); require ARGV.fetch(0)' "$(GEM)"; \
		status=$$?; rm -rf "$$gem_home"; [ "$$status" -eq 0 ] || exit "$$status"

audit: install
	@for project in $(PROJECTS); do \
		printf '\n\033[1m==> audit %s\033[0m\n' "$$project"; \
		(cd "$$project" && bundle exec bundle-audit check --update) || exit 1; \
	done

# The lint and the suite of each gem on its oldest supported Ruby line, in that line's official image, from a copy
# of this working tree, so nothing installed for the local Ruby leaks in and nothing is written back. --pull always
# fetches the image's latest patch release, which verify-ruby then checks, and verify-lock installs the committed
# lock before anything can change it.
check-floor:
	@for gem in $(GEMS); do \
		$(MAKE) --no-print-directory _check-floor GEM="$$gem" || exit 1; \
	done

_check-floor:
	@printf '\n\033[1m==> check-floor %s on %s\033[0m\n' "$(GEM)" "$(FLOOR_IMAGE_$(GEM))"
	docker run --rm --pull always --volume "$(CURDIR)":/source:ro $(FLOOR_IMAGE_$(GEM)) sh -c '\
		mkdir /work \
		&& tar -C /source --exclude=./.git --exclude=./dist --exclude=.bundle --exclude=vendor -cf - . \
			| tar -C /work -xf - \
		&& make -C /work verify-ruby verify-lock lint test GEMS=$(GEM) SAMPLES='

# The fast loop while working.
check: lint test

# Everything CI runs. The pre-push hook calls this.
check-all: verify-ruby verify-lock lint test test-lowest test-release samples samples-local build audit check-floor
	@printf '\n\033[1m✓ all checks passed\033[0m\n'

# Measurements, not checks: what a read, a payload and an init cost, and what forking for each job costs. Their
# numbers depend on the machine, so nothing in check-all runs them. See profiling/README.md.
profile: install
	@cd $(SDK) && bundle exec ruby ../profiling/benchmark.rb

profile-fork-per-job: install
	@cd $(SDK) && bundle exec ruby ../profiling/fork_per_job.rb

clean:
	rm -rf dist
	@for sample in $(SAMPLES); do \
		rm -rf "$$sample/vendor" "$$sample/log" "$$sample/tmp"; \
	done
