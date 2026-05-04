#!/usr/bin/env bash
# fetch_kit.sh — clone a starter kit repo to a local cache for read-only inspection.
#
# Usage: fetch_kit.sh <kit> <branch> <dest>
#   kit:    one of vue-starter-kit, react-starter-kit, livewire-starter-kit
#   branch: e.g. main, workos
#   dest:   destination directory; if it already exists, fetch updates instead
#
# We use a regular (non-bare) clone with depth 500 — enough to cover ~1-2 years
# of releases for these kits without pulling the entire history.

set -euo pipefail

kit="$1"
branch="$2"
dest="$3"

case "$kit" in
    vue-starter-kit|react-starter-kit|livewire-starter-kit) ;;
    *)
        echo "ERROR: unknown kit '$kit'." >&2
        echo "Supported: vue-starter-kit, react-starter-kit, livewire-starter-kit" >&2
        exit 1
        ;;
esac

url="https://github.com/laravel/$kit.git"

if [[ -d "$dest/.git" ]]; then
    if ! git -C "$dest" remote get-url origin 2>/dev/null | grep -q "$kit"; then
        echo "ERROR: '$dest' exists but is not a clone of $kit." >&2
        exit 2
    fi
    git -C "$dest" fetch --depth 500 origin "$branch" >/dev/null
    git -C "$dest" checkout -q "origin/$branch"
else
    git clone --quiet --depth 500 --branch "$branch" "$url" "$dest"
fi

echo "fetch_kit: $kit@$branch ready at $dest"
