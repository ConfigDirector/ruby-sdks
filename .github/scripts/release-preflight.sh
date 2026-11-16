#!/usr/bin/env sh
#
# Decides what the release workflow releases for one gem, and fails when nothing must be released: reads
# the version the gem's gemspec declares, refuses a version that is not X.Y.Z, one whose tag already exists
# and one RubyGems already has, and takes the release notes from the gem's CHANGELOG.md section for that
# version.
# Writes `version` and `tag` to $GITHUB_OUTPUT when it is set, and the notes to the given file. It asks the
# gem server that RUBYGEMS_HOST names, as `gem push` does, which is https://rubygems.org when unset.
# `make test-release` runs it against throwaway repositories.
#
# Usage: release-preflight.sh <gem> <notes-file>, from the repository root.

set -eu

gem=${1:-}
notes_file=${2:-}

if [ -z "$gem" ] || [ -z "$notes_file" ]; then
    echo "usage: $0 <gem> <notes-file>" >&2
    exit 2
fi

gemspec="$gem/$gem.gemspec"
changelog="$gem/CHANGELOG.md"
rubygems_host=${RUBYGEMS_HOST:-https://rubygems.org}

for file in "$gemspec" "$changelog"; do
    if [ ! -f "$file" ]; then
        echo "Cannot find $file. Run this from the repository root." >&2
        exit 1
    fi
done

if ! version=$(ruby -e 'print Gem::Specification.load(ARGV.fetch(0))&.version' "$gemspec") || [ -z "$version" ]; then
    echo "Could not read a version from $gemspec." >&2
    exit 1
fi

if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Version '$version' is not a release: a release is X.Y.Z, such as 1.2.3." >&2
    echo "RubyGems writes a dash as .pre., so a development version such as 0.1.0-dev reads 0.1.0.pre.dev" >&2
    echo "here. Set the version that $gemspec declares." >&2
    exit 1
fi

tag="$gem-v$version"

if ! tags_in_this_repository=$(git ls-remote --tags origin "refs/tags/$tag"); then
    echo "Could not read the tags of this repository's origin." >&2
    exit 1
fi

if [ -n "$tags_in_this_repository" ]; then
    echo "$tag already exists, so $gem $version has been released before. RubyGems never accepts a" >&2
    echo "version twice: to ship a change, raise the version that $gemspec declares, open a new" >&2
    echo "$changelog section, and run this again." >&2
    exit 1
fi

version_on_rubygems=$(curl --silent --max-time 30 --output /dev/null --write-out '%{http_code}' \
    "$rubygems_host/api/v2/rubygems/$gem/versions/$version.json") || version_on_rubygems="no answer"

case "$version_on_rubygems" in
    404) ;;
    200)
        echo "RubyGems already has $gem $version, and never accepts a version twice, while this" >&2
        echo "repository has no $tag tag. To ship a change, raise the version that $gemspec declares," >&2
        echo "open a new $changelog section, and run this again. To finish a release that stopped after" >&2
        echo "its push, see Releasing in CONTRIBUTING.md." >&2
        exit 1
        ;;
    "no answer")
        echo "Could not ask $rubygems_host whether it has $gem $version (no answer). Run this again." >&2
        exit 1
        ;;
    *)
        echo "Could not ask $rubygems_host whether it has $gem $version (HTTP $version_on_rubygems). Run" >&2
        echo "this again." >&2
        exit 1
        ;;
esac

heading="## [$version]"

if ! awk -v heading="$heading" '
    /^## / {
        if (inside) exit
        inside = ($0 == heading || index($0, heading " ") == 1)
        if (inside) found = 1
        next
    }
    inside { lines[++count] = $0 }
    END {
        if (!found) exit 3
        first = 1
        while (first <= count && lines[first] ~ /^[[:space:]]*$/) first++
        last = count
        while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
        for (i = first; i <= last; i++) print lines[i]
    }
' "$changelog" > "$notes_file"; then
    rm -f "$notes_file"
    echo "$changelog has no '$heading' section. Rename its '## [Unreleased]' heading to" >&2
    echo "'$heading - YYYY-MM-DD' and open a fresh one above it before releasing." >&2
    exit 1
fi

if [ ! -s "$notes_file" ]; then
    rm -f "$notes_file"
    echo "The '$heading' section in $changelog is empty, so there are no release notes to publish." >&2
    exit 1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "version=$version"
        echo "tag=$tag"
    } >> "$GITHUB_OUTPUT"
fi

echo "Releasing $gem $version as $tag with these notes:"
echo
cat "$notes_file"
