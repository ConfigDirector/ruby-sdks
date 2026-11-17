#!/usr/bin/env sh
#
# Runs the release scripts one scenario at a time: the releases they must make and every refusal. Git works
# on throwaway repositories, and a local server stands in for RubyGems and for the endpoint GitHub gives a
# job its identity token from, so nothing here reaches either. `make test-release` runs this.

set -eu

scripts_directory=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$scripts_directory/../.." && pwd)
preflight="$scripts_directory/release-preflight.sh"
verify_built_gem="$repository_root/tools/verify-built-gem.rb"
publish_gem="$scripts_directory/publish-gem.rb"
sandbox=$(mktemp -d)
stand_in="$sandbox/stand-in"
failures=0
scenario_failed=0

# Nothing from the developer's git configuration (hooks, signing, identity) reaches the throwaway
# repositories.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

mkdir -p "$stand_in"
ruby "$scripts_directory/release-test-stand-in-server.rb" "$stand_in" &
stand_in_process=$!
trap 'kill "$stand_in_process" 2>/dev/null || true; wait "$stand_in_process" 2>/dev/null || true; rm -rf "$sandbox"' EXIT
trap 'exit 130' INT TERM

waits=0
while [ ! -f "$stand_in/port" ]; do
    waits=$((waits + 1))
    if [ "$waits" -gt 100 ]; then
        echo "The stand-in server did not start." >&2
        exit 1
    fi
    sleep 0.1
done
stand_in_url="http://127.0.0.1:$(cat "$stand_in/port")"

# Starts a scenario: the stand-in server forgets its answers and the requests it received, so it answers
# 404 to everything, as RubyGems does for a gem or a version it does not have.
scenario() {
    scenario_name=$1
    directory="$sandbox/$scenario_name"
    mkdir -p "$directory"
    rm -rf "$stand_in/answers" "$stand_in/requests"
}

# Scripts the stand-in server's answer to one exchange, named by its method and its path with every slash
# written as an underscore, such as GET_api_v1_gems.
stand_in_answers() {
    mkdir -p "$stand_in/answers"
    printf '%s\n%s' "$2" "${3:-}" > "$stand_in/answers/$1"
}

gemspec() {
    printf 'Gem::Specification.new do |spec|\n  spec.name = "%s"\n  spec.version = "%s"\n  spec.authors = ["ConfigDirector"]\n  spec.summary = "A gem."\nend\n' "$1" "$2"
}

released_changelog() {
    printf '# Changelog\n\n## [Unreleased]\n\n## [%s] - 2026-11-16\n\n### Added\n\n- A client.\n\n## [0.0.1] - 2026-11-01\n\n### Added\n\n- The repository.\n' "$1"
}

# A clone of a bare origin that holds one gem with the given gemspec and CHANGELOG.md, pushed, as the
# workflow's checkout holds this repository. Sets $clone.
repository_with() {
    clone="$directory/clone"
    git init -q --bare --initial-branch=main "$directory/origin"
    git clone -q "$directory/origin" "$clone" 2>/dev/null
    mkdir -p "$clone/$1"
    printf '%s\n' "$2" > "$clone/$1/$1.gemspec"
    printf '%s\n' "$3" > "$clone/$1/CHANGELOG.md"
    git -C "$clone" add .
    git -C "$clone" commit -q -m "Prepare the release"
    git -C "$clone" push -q origin HEAD
}

push_tag_to_origin() {
    git -C "$clone" tag "$1"
    git -C "$clone" push -q origin "$1"
}

# Runs the preflight from the clone, as the workflow does from its checkout, with the stand-in server as
# RubyGems. Sets $status, $outputs_file, $notes_file, $stderr_file.
run_preflight() {
    outputs_file="$directory/github-output"
    notes_file="$directory/release-notes.md"
    stderr_file="$directory/stderr"
    : > "$outputs_file"
    status=0
    (cd "$clone" && GITHUB_OUTPUT="$outputs_file" RUBYGEMS_HOST="${rubygems_host:-$stand_in_url}" "$preflight" "$1" "$notes_file") \
        > "$directory/stdout" 2> "$stderr_file" || status=$?
}

fail() {
    printf 'FAIL %s: %s\n' "$scenario_name" "$1"
    [ "$scenario_failed" -eq 1 ] || failures=$((failures + 1))
    scenario_failed=1
}

assert_status() {
    [ "$status" -eq "$1" ] || fail "exit status was $status, expected $1 (stderr: $(cat "$stderr_file"))"
}

assert_outputs() {
    actual=$(cat "$outputs_file")
    [ "$actual" = "$1" ] || fail "outputs were '$actual', expected '$1'"
}

assert_notes() {
    actual=$(cat "$notes_file" 2>/dev/null || true)
    [ "$actual" = "$1" ] || fail "notes were '$actual', expected '$1'"
}

assert_stderr_mentions() {
    grep -qF -- "$1" "$stderr_file" || fail "stderr does not mention '$1': $(cat "$stderr_file")"
}

assert_refused_with() {
    assert_status 1
    assert_stderr_mentions "$1"
    assert_outputs ""
    [ ! -e "$notes_file" ] || fail "notes were written for a refused release"
}

requires_mfa='spec.metadata = { "rubygems_mfa_required" => "true" }'

# Builds a gem named throwaway that packs the given files, with the given line of its gemspec deciding its
# metadata. Sets $built_gem.
built_gem_with() {
    gem_directory="$directory/gem"
    metadata=$1
    shift
    for file in "$@"; do
        mkdir -p "$(dirname "$gem_directory/$file")"
        echo "A line." > "$gem_directory/$file"
    done
    printf 'Gem::Specification.new do |spec|\n  spec.name = "throwaway"\n  spec.version = "0.1.0"\n  spec.authors = ["ConfigDirector"]\n  spec.summary = "A gem."\n  %s\n  spec.files = %%w[%s]\nend\n' "$metadata" "$*" \
        > "$gem_directory/throwaway.gemspec"
    (cd "$gem_directory" && gem build --quiet throwaway.gemspec) > "$directory/gem-build" 2>&1
    built_gem="$gem_directory/throwaway-0.1.0.gem"
}

# Sets $status and $stderr_file.
run_verify_built_gem() {
    stderr_file="$directory/stderr"
    status=0
    ruby "$verify_built_gem" "$built_gem" > "$directory/stdout" 2> "$stderr_file" || status=$?
}

# Scripts the stand-in server as GitHub handing the job its identity token and as RubyGems accepting that
# token from a trusted publisher.
rubygems_trusts_this_workflow() {
    stand_in_answers GET_identity-token 200 '{"value":"identity-token-of-the-job"}'
    stand_in_answers POST_api_v1_oidc_trusted_publisher_exchange_token 201 \
        '{"rubygems_api_key":"rubygems_key_of_this_run","name":"GitHub Actions ConfigDirector/ruby-sdks @ .github/workflows/release-throwaway.yml 2026-11-16T10:00:00Z","scopes":["push_rubygem"],"owner":"the-owning-account","expires_at":"2026-11-16T10:15:00.000Z"}'
}

# Runs the publish script on $built_gem as the publish job does, with the stand-in server as RubyGems and
# as the endpoint GitHub gives the job for its identity token. A scenario replaces one of the job's
# variables by setting $identity_token_request_url, $owner_id or $dry_run first. Sets $status, $stdout_file
# and $stderr_file.
run_publish_gem() {
    stdout_file="$directory/stdout"
    stderr_file="$directory/stderr"
    mkdir -p "$directory/home"
    status=0
    HOME="$directory/home" \
        ACTIONS_ID_TOKEN_REQUEST_URL="${identity_token_request_url-$stand_in_url/identity-token?api-version=2.0}" \
        ACTIONS_ID_TOKEN_REQUEST_TOKEN=request-token-of-the-job \
        RUBYGEMS_OWNER_ID="${owner_id-424242}" \
        DRY_RUN="${dry_run-false}" \
        RUBYGEMS_HOST="$stand_in_url" \
        ruby "$publish_gem" "$built_gem" > "$stdout_file" 2> "$stderr_file" || status=$?
    unset identity_token_request_url owner_id dry_run
}

assert_stand_in_did_not_receive() {
    [ ! -e "$stand_in/requests/$1.target" ] || fail "the stand-in server received $1"
}

assert_stand_in_received_nothing() {
    [ ! -e "$stand_in/requests" ] || fail "the stand-in server received $(ls "$stand_in/requests")"
}

assert_request_target() {
    actual=$(cat "$stand_in/requests/$1.target" 2>/dev/null || true)
    [ "$actual" = "$2" ] || fail "the target of $1 was '$actual', expected '$2'"
}

assert_request_header() {
    grep -qixF -- "$2" "$stand_in/requests/$1.headers" 2>/dev/null \
        || fail "$1 had no header '$2': $(cat "$stand_in/requests/$1.headers" 2>/dev/null || true)"
}

assert_request_body() {
    actual=$(cat "$stand_in/requests/$1.body" 2>/dev/null || true)
    [ "$actual" = "$2" ] || fail "the body of $1 was '$actual', expected '$2'"
}

assert_output_does_not_mention() {
    if grep -qF -- "$1" "$stdout_file" "$stderr_file"; then
        fail "the output mentions '$1': $(cat "$stdout_file" "$stderr_file")"
    fi
}

# RubyGems trusts one workflow file per gem, so the release workflows cannot share their jobs, and each is
# the server SDK's with the gem's name in place of the server SDK's.
assert_release_workflow_is_the_server_sdks_for() {
    workflows="$repository_root/.github/workflows"
    sed "s/configdirector-server-sdk/$1/g" "$workflows/release-configdirector-server-sdk.yml" \
        | cmp -s - "$workflows/release-$1.yml" \
        || fail "release-$1.yml is not release-configdirector-server-sdk.yml with $1 as the gem"
}

assert_carries_the_license_of_this_repository() {
    cmp -s "$repository_root/LICENSE" "$repository_root/$1/LICENSE" || fail "$1/LICENSE is not a copy of LICENSE"
}

# Ends a scenario: prints its name when every assertion since the last one held.
pass() {
    [ "$scenario_failed" -eq 1 ] || printf 'ok   %s\n' "$scenario_name"
    scenario_failed=0
}

scenario releases_the_version_the_gem_declares_with_its_changelog_section_as_notes
repository_with configdirector-server-sdk "$(gemspec configdirector-server-sdk 0.1.0)" "$(released_changelog 0.1.0)"
run_preflight configdirector-server-sdk
assert_status 0
assert_outputs "version=0.1.0
tag=configdirector-server-sdk-v0.1.0"
assert_notes "### Added

- A client."
pass

scenario names_the_tag_of_the_provider_after_its_gem
repository_with configdirector-openfeature-server-provider "$(gemspec configdirector-openfeature-server-provider 0.1.0)" "$(released_changelog 0.1.0)"
run_preflight configdirector-openfeature-server-provider
assert_status 0
assert_outputs "version=0.1.0
tag=configdirector-openfeature-server-provider-v0.1.0"
pass

scenario releases_the_bare_name_gem_while_that_version_of_the_server_sdk_is_tagged_and_on_rubygems
repository_with configdirector "$(gemspec configdirector 0.1.0)" "$(released_changelog 0.1.0)"
push_tag_to_origin configdirector-server-sdk-v0.1.0
stand_in_answers GET_api_v2_rubygems_configdirector-server-sdk_versions_0.1.0.json 200 '{"version":"0.1.0"}'
run_preflight configdirector
assert_status 0
assert_outputs "version=0.1.0
tag=configdirector-v0.1.0"
pass

scenario refuses_a_version_whose_tag_already_exists
repository_with configdirector-server-sdk "$(gemspec configdirector-server-sdk 0.1.0)" "$(released_changelog 0.1.0)"
push_tag_to_origin configdirector-server-sdk-v0.1.0
run_preflight configdirector-server-sdk
assert_refused_with "configdirector-server-sdk-v0.1.0 already exists"
pass

scenario refuses_a_version_rubygems_already_has
repository_with configdirector-server-sdk "$(gemspec configdirector-server-sdk 0.1.0)" "$(released_changelog 0.1.0)"
stand_in_answers GET_api_v2_rubygems_configdirector-server-sdk_versions_0.1.0.json 200 '{"version":"0.1.0"}'
run_preflight configdirector-server-sdk
assert_refused_with "RubyGems already has configdirector-server-sdk 0.1.0"
pass

scenario refuses_when_rubygems_answers_with_an_error
repository_with configdirector-server-sdk "$(gemspec configdirector-server-sdk 0.1.0)" "$(released_changelog 0.1.0)"
stand_in_answers GET_api_v2_rubygems_configdirector-server-sdk_versions_0.1.0.json 503
run_preflight configdirector-server-sdk
assert_refused_with "Could not ask $stand_in_url whether it has configdirector-server-sdk 0.1.0 (HTTP 503)"
pass

scenario refuses_when_rubygems_cannot_be_reached
repository_with configdirector-server-sdk "$(gemspec configdirector-server-sdk 0.1.0)" "$(released_changelog 0.1.0)"
rubygems_host=http://127.0.0.1:1
run_preflight configdirector-server-sdk
unset rubygems_host
assert_refused_with "Could not ask http://127.0.0.1:1 whether it has configdirector-server-sdk 0.1.0 (no answer)"
pass

scenario refuses_when_the_tags_of_this_repository_cannot_be_read
repository_with configdirector-server-sdk "$(gemspec configdirector-server-sdk 0.1.0)" "$(released_changelog 0.1.0)"
git -C "$clone" remote set-url origin "$directory/moved-away"
run_preflight configdirector-server-sdk
assert_refused_with "Could not read the tags of this repository's origin"
pass

scenario refuses_a_version_without_a_changelog_section
repository_with configdirector-server-sdk "$(gemspec configdirector-server-sdk 0.1.0)" "$(released_changelog 0.0.2)"
run_preflight configdirector-server-sdk
assert_refused_with "no '## [0.1.0]' section"
pass

scenario refuses_a_version_whose_only_changelog_section_is_of_a_longer_version
repository_with configdirector-server-sdk "$(gemspec configdirector-server-sdk 0.1.0)" "$(released_changelog 0.1.0.1)"
run_preflight configdirector-server-sdk
assert_refused_with "no '## [0.1.0]' section"
pass

scenario refuses_a_version_whose_changelog_section_is_empty
repository_with configdirector-server-sdk "$(gemspec configdirector-server-sdk 0.1.0)" "$(printf '# Changelog\n\n## [Unreleased]\n\n## [0.1.0] - 2026-11-16\n\n## [0.0.1] - 2026-11-01\n\n- The repository.\n')"
run_preflight configdirector-server-sdk
assert_refused_with "'## [0.1.0]' section in configdirector-server-sdk/CHANGELOG.md is empty"
pass

scenario refuses_the_development_version_of_a_gem_never_prepared_for_a_release
repository_with configdirector-server-sdk "$(gemspec configdirector-server-sdk 0.1.0-dev)" "$(released_changelog 0.1.0-dev)"
run_preflight configdirector-server-sdk
assert_refused_with "Version '0.1.0.pre.dev' is not a release"
pass

scenario refuses_a_version_with_a_v_prefix
repository_with configdirector-server-sdk "$(gemspec configdirector-server-sdk v0.1.0)" "$(released_changelog 0.1.0)"
run_preflight configdirector-server-sdk
assert_refused_with "Could not read a version from configdirector-server-sdk/configdirector-server-sdk.gemspec"
pass

scenario refuses_a_gem_directory_that_does_not_exist
repository_with configdirector-server-sdk "$(gemspec configdirector-server-sdk 0.1.0)" "$(released_changelog 0.1.0)"
run_preflight configdirector-client-sdk
assert_refused_with "Cannot find configdirector-client-sdk/configdirector-client-sdk.gemspec"
pass

scenario accepts_a_built_gem_that_holds_its_code_its_signatures_and_its_documents
built_gem_with "$requires_mfa" lib/throwaway.rb lib/throwaway/client.rb sig/throwaway.rbs .yardopts CHANGELOG.md LICENSE README.md
run_verify_built_gem
assert_status 0
pass

scenario accepts_a_built_gem_without_code_that_holds_its_documents
built_gem_with "$requires_mfa" CHANGELOG.md LICENSE README.md
run_verify_built_gem
assert_status 0
pass

scenario refuses_a_built_gem_that_holds_a_spec_file
built_gem_with "$requires_mfa" lib/throwaway.rb sig/throwaway.rbs spec/throwaway_spec.rb CHANGELOG.md LICENSE README.md
run_verify_built_gem
assert_status 1
assert_stderr_mentions "throwaway-0.1.0.gem holds spec/throwaway_spec.rb"
pass

scenario refuses_a_built_gem_that_holds_a_sample
built_gem_with "$requires_mfa" lib/throwaway.rb sig/throwaway.rbs samples/rails/config.ru CHANGELOG.md LICENSE README.md
run_verify_built_gem
assert_status 1
assert_stderr_mentions "throwaway-0.1.0.gem holds samples/rails/config.ru"
pass

scenario refuses_a_built_gem_that_holds_a_development_file
built_gem_with "$requires_mfa" lib/throwaway.rb sig/throwaway.rbs Gemfile.lock CHANGELOG.md LICENSE README.md
run_verify_built_gem
assert_status 1
assert_stderr_mentions "throwaway-0.1.0.gem holds Gemfile.lock"
pass

scenario refuses_a_built_gem_that_holds_a_file_under_lib_that_is_not_ruby
built_gem_with "$requires_mfa" lib/throwaway.rb lib/throwaway.rb.orig sig/throwaway.rbs CHANGELOG.md LICENSE README.md
run_verify_built_gem
assert_status 1
assert_stderr_mentions "throwaway-0.1.0.gem holds lib/throwaway.rb.orig"
pass

scenario refuses_a_built_gem_that_holds_ruby_code_outside_lib
built_gem_with "$requires_mfa" lib/throwaway.rb sig/throwaway.rbs profiling/benchmark.rb CHANGELOG.md LICENSE README.md
run_verify_built_gem
assert_status 1
assert_stderr_mentions "throwaway-0.1.0.gem holds profiling/benchmark.rb"
pass

scenario refuses_a_built_gem_whose_code_has_no_signatures
built_gem_with "$requires_mfa" lib/throwaway.rb CHANGELOG.md LICENSE README.md
run_verify_built_gem
assert_status 1
assert_stderr_mentions "throwaway-0.1.0.gem holds Ruby code and no RBS signatures under sig/"
pass

scenario refuses_a_built_gem_without_its_license
built_gem_with "$requires_mfa" lib/throwaway.rb sig/throwaway.rbs CHANGELOG.md README.md
run_verify_built_gem
assert_status 1
assert_stderr_mentions "throwaway-0.1.0.gem lacks LICENSE"
pass

scenario refuses_a_built_gem_without_its_readme
built_gem_with "$requires_mfa" lib/throwaway.rb sig/throwaway.rbs CHANGELOG.md LICENSE
run_verify_built_gem
assert_status 1
assert_stderr_mentions "throwaway-0.1.0.gem lacks README.md"
pass

scenario refuses_a_built_gem_without_its_changelog
built_gem_with "$requires_mfa" lib/throwaway.rb sig/throwaway.rbs LICENSE README.md
run_verify_built_gem
assert_status 1
assert_stderr_mentions "throwaway-0.1.0.gem lacks CHANGELOG.md"
pass

scenario refuses_a_built_gem_whose_owners_need_no_multi_factor_authentication
built_gem_with "" lib/throwaway.rb sig/throwaway.rbs CHANGELOG.md LICENSE README.md
run_verify_built_gem
assert_status 1
assert_stderr_mentions "throwaway-0.1.0.gem does not set rubygems_mfa_required"
pass

scenario refuses_a_built_gem_that_turns_the_multi_factor_authentication_requirement_off
built_gem_with 'spec.metadata = { "rubygems_mfa_required" => "false" }' lib/throwaway.rb sig/throwaway.rbs CHANGELOG.md LICENSE README.md
run_verify_built_gem
assert_status 1
assert_stderr_mentions "throwaway-0.1.0.gem does not set rubygems_mfa_required"
pass

scenario pushes_the_gem_with_the_key_rubygems_gave_for_the_identity_token_of_the_job
built_gem_with "$requires_mfa" CHANGELOG.md LICENSE README.md
rubygems_trusts_this_workflow
stand_in_answers POST_api_v1_gems 200 "Successfully registered gem: throwaway (0.1.0)"
run_publish_gem
assert_status 0
assert_request_target GET_identity-token "/identity-token?api-version=2.0&audience=rubygems.org"
assert_request_header GET_identity-token "Authorization: bearer request-token-of-the-job"
assert_request_body POST_api_v1_oidc_trusted_publisher_exchange_token '{"jwt":"identity-token-of-the-job","owner":"424242"}'
assert_request_header POST_api_v1_oidc_trusted_publisher_exchange_token "Content-Type: application/json"
assert_request_header POST_api_v1_gems "Authorization: rubygems_key_of_this_run"
cmp -s "$built_gem" "$stand_in/requests/POST_api_v1_gems.body" || fail "the pushed body is not the built gem"
pass

scenario a_dry_run_exchanges_the_identity_token_and_pushes_nothing
built_gem_with "$requires_mfa" CHANGELOG.md LICENSE README.md
rubygems_trusts_this_workflow
stand_in_answers POST_api_v1_gems 200 "Successfully registered gem: throwaway (0.1.0)"
dry_run=true
run_publish_gem
assert_status 0
assert_request_body POST_api_v1_oidc_trusted_publisher_exchange_token '{"jwt":"identity-token-of-the-job","owner":"424242"}'
assert_stand_in_did_not_receive POST_api_v1_gems
grep -qF "the-owning-account" "$stdout_file" || fail "the output does not name the account RubyGems read the owner as: $(cat "$stdout_file")"
pass

scenario keeps_the_key_out_of_the_log_of_a_release
built_gem_with "$requires_mfa" CHANGELOG.md LICENSE README.md
rubygems_trusts_this_workflow
stand_in_answers POST_api_v1_gems 200 "Successfully registered gem: throwaway (0.1.0)"
run_publish_gem
assert_status 0
grep -qxF "::add-mask::rubygems_key_of_this_run" "$stdout_file" || fail "the key is not masked: $(cat "$stdout_file")"
grep -vxF "::add-mask::rubygems_key_of_this_run" "$stdout_file" > "$directory/stdout-after-the-mask" || true
stdout_file="$directory/stdout-after-the-mask"
assert_output_does_not_mention rubygems_key_of_this_run
assert_output_does_not_mention identity-token-of-the-job
pass

scenario pushes_nothing_when_rubygems_does_not_trust_this_workflow
built_gem_with "$requires_mfa" CHANGELOG.md LICENSE README.md
stand_in_answers GET_identity-token 200 '{"value":"identity-token-of-the-job"}'
stand_in_answers POST_api_v1_oidc_trusted_publisher_exchange_token 404 "Not Found"
stand_in_answers POST_api_v1_gems 200 "Successfully registered gem: throwaway (0.1.0)"
run_publish_gem
assert_status 1
assert_stderr_mentions "RubyGems did not exchange the identity token of this job for a key (HTTP 404): Not Found"
assert_stand_in_did_not_receive POST_api_v1_gems
pass

scenario pushes_nothing_when_rubygems_does_not_know_the_owning_account
built_gem_with "$requires_mfa" CHANGELOG.md LICENSE README.md
stand_in_answers GET_identity-token 200 '{"value":"identity-token-of-the-job"}'
stand_in_answers POST_api_v1_oidc_trusted_publisher_exchange_token 400 'Unknown owner "424242"'
stand_in_answers POST_api_v1_gems 200 "Successfully registered gem: throwaway (0.1.0)"
run_publish_gem
assert_status 1
assert_stderr_mentions 'RubyGems did not exchange the identity token of this job for a key (HTTP 400): Unknown owner "424242"'
assert_stand_in_did_not_receive POST_api_v1_gems
pass

scenario asks_rubygems_for_nothing_when_github_gives_the_job_no_identity_token
built_gem_with "$requires_mfa" CHANGELOG.md LICENSE README.md
rubygems_trusts_this_workflow
stand_in_answers GET_identity-token 403 '{"message":"denied"}'
run_publish_gem
assert_status 1
assert_stderr_mentions "GitHub did not give this job an identity token (HTTP 403)"
assert_stand_in_did_not_receive POST_api_v1_oidc_trusted_publisher_exchange_token
assert_stand_in_did_not_receive POST_api_v1_gems
pass

scenario asks_for_nothing_in_a_job_that_may_not_request_an_identity_token
built_gem_with "$requires_mfa" CHANGELOG.md LICENSE README.md
rubygems_trusts_this_workflow
identity_token_request_url=
run_publish_gem
assert_status 1
assert_stderr_mentions "This job may not request an identity token from GitHub"
assert_stand_in_received_nothing
pass

scenario asks_for_nothing_without_the_id_of_the_owning_account
built_gem_with "$requires_mfa" CHANGELOG.md LICENSE README.md
rubygems_trusts_this_workflow
owner_id=
run_publish_gem
assert_status 1
assert_stderr_mentions "RUBYGEMS_OWNER_ID is ''"
assert_stand_in_received_nothing
pass

scenario asks_for_nothing_when_the_owning_account_is_named_by_its_handle
built_gem_with "$requires_mfa" CHANGELOG.md LICENSE README.md
rubygems_trusts_this_workflow
owner_id=the-owning-account
run_publish_gem
assert_status 1
assert_stderr_mentions "RUBYGEMS_OWNER_ID is 'the-owning-account'"
assert_stand_in_received_nothing
pass

scenario asks_for_nothing_when_it_is_not_told_whether_this_is_a_dry_run
built_gem_with "$requires_mfa" CHANGELOG.md LICENSE README.md
rubygems_trusts_this_workflow
dry_run=
run_publish_gem
assert_status 1
assert_stderr_mentions "DRY_RUN is ''"
assert_stand_in_received_nothing
pass

scenario fails_when_rubygems_refuses_the_push
built_gem_with "$requires_mfa" CHANGELOG.md LICENSE README.md
rubygems_trusts_this_workflow
stand_in_answers POST_api_v1_gems 403 "You are not allowed to push this gem."
run_publish_gem
assert_status 1
grep -qF "You are not allowed to push this gem." "$stdout_file" "$stderr_file" || fail "the output does not hold RubyGems' reason: $(cat "$stdout_file" "$stderr_file")"
pass

scenario the_release_workflow_of_the_provider_differs_from_the_server_sdks_by_the_name_of_the_gem_alone
assert_release_workflow_is_the_server_sdks_for configdirector-openfeature-server-provider
pass

scenario the_release_workflow_of_the_bare_name_gem_differs_from_the_server_sdks_by_the_name_of_the_gem_alone
assert_release_workflow_is_the_server_sdks_for configdirector
pass

scenario the_server_sdk_carries_the_license_of_this_repository
assert_carries_the_license_of_this_repository configdirector-server-sdk
pass

scenario the_provider_carries_the_license_of_this_repository
assert_carries_the_license_of_this_repository configdirector-openfeature-server-provider
pass

scenario the_bare_name_gem_carries_the_license_of_this_repository
assert_carries_the_license_of_this_repository configdirector
pass

if [ "$failures" -ne 0 ]; then
    printf '\n%s scenario(s) failed\n' "$failures"
    exit 1
fi
