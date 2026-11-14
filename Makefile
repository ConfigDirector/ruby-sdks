.PHONY: install hooks verify-ruby verify-lock format lint test test-lowest samples-local build audit check-floor \
	_check-floor check check-all clean

# Every gem this repository publishes, each in a directory named after it. Narrow a target to one of them with,
# for example, `make test GEMS=configdirector-server-sdk`.
SDK := configdirector-server-sdk
PROVIDER := configdirector-openfeature-server-provider
GEMS := $(SDK) $(PROVIDER)

# Sample applications, each a Bundler project under samples/<gem>/<framework> that takes the gems from this working
# tree through a path: entry until their first release. `install`, `verify-lock`, `format`, `lint`, `audit` and
# `clean` run on each sample as well as on each gem; `SAMPLES=` leaves the samples out.
SAMPLES := samples/configdirector-server-sdk/rails

PROJECTS := $(GEMS) $(SAMPLES)

# The official image of each gem's oldest supported Ruby line. `check-floor` runs the gem's lint and suite in it.
FLOOR_IMAGE_$(SDK) := ruby:3.3
FLOOR_IMAGE_$(PROVIDER) := ruby:3.4

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
		printf '\n\033[1m==> lint %s\033[0m\n' "$$gem"; \
		(cd "$$gem" && bundle exec rubocop && bundle exec steep check) || exit 1; \
	done
	@for sample in $(SAMPLES); do \
		printf '\n\033[1m==> lint %s\033[0m\n' "$$sample"; \
		(cd "$$sample" && bundle exec rubocop) || exit 1; \
	done

test: install
	@for gem in $(GEMS); do \
		printf '\n\033[1m==> test %s\033[0m\n' "$$gem"; \
		(cd "$$gem" && bundle exec rspec) || exit 1; \
	done

# The same suites against the lowest version of each runtime dependency that the gemspec allows. Without this a
# floor such as `logger ~> 1.6` is only ever a guess, because the lock picks the newest. Bundler resolves into a
# throwaway Gemfile and lock, so the committed lock stays as it is.
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

# The suite of each sample against the gems in this working tree, which is what catches a change to a gem that breaks
# the code an application writes against it. Each sample installs its own bundle, so a Ruby line that one of the
# gems does not support, such as 3.3 for the provider, can still run the samples of the other.
samples-local:
	@for sample in $(SAMPLES); do \
		printf '\n\033[1m==> samples-local %s\033[0m\n' "$$sample"; \
		(cd "$$sample" && bundle install --quiet && bundle exec rspec) || exit 1; \
	done

# One .gem file per gem under dist/. --strict turns every warning about the gemspec into a failure.
build:
	@rm -rf dist
	@mkdir dist
	@for gem in $(GEMS); do \
		printf '\n\033[1m==> build %s\033[0m\n' "$$gem"; \
		(cd "$$gem" && gem build --strict --quiet "$$gem.gemspec" && mv "$$gem"-*.gem ../dist/) || exit 1; \
	done
	@ls dist

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
check-all: verify-ruby verify-lock lint test test-lowest samples-local build audit check-floor
	@printf '\n\033[1m✓ all checks passed\033[0m\n'

clean:
	rm -rf dist
	@for sample in $(SAMPLES); do \
		rm -rf "$$sample/vendor" "$$sample/log" "$$sample/tmp"; \
	done
