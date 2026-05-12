#!/usr/bin/env bash
# fetch_kit.sh — clone (or update) a Laravel starter kit repo into a local
# cache so other scripts can read upstream state.
#
# Usage: fetch_kit.sh <kit> <branch> [dest]
#   <kit>    one of: vue-starter-kit, react-starter-kit, svelte-starter-kit, livewire-starter-kit
#   <branch> one of: main, teams, workos, workos-teams
#   [dest]   destination dir (default: /tmp/starter-kit-<kit>)
#
# Idempotent: if dest already has a clone of the same repo, fetches the
# branch and resets to upstream rather than re-cloning. Prints the
# destination path on stdout so the caller can capture it (e.g.
# `kit_dir=$(scripts/fetch_kit.sh vue-starter-kit main)`).

set -euo pipefail

usage() {
    echo "Usage: $0 <kit> <branch> [dest]" >&2
    exit 2
}

[[ $# -lt 2 ]] && usage

kit="$1"
branch="$2"
dest="${3:-/tmp/starter-kit-$kit}"

case "$kit" in
    vue-starter-kit|react-starter-kit|svelte-starter-kit|livewire-starter-kit) ;;
    *)
        echo "ERROR: unknown kit '$kit'" >&2
        echo "Supported: vue-starter-kit, react-starter-kit, svelte-starter-kit, livewire-starter-kit" >&2
        exit 3
        ;;
esac

url="https://github.com/laravel/$kit.git"

if [[ -d "$dest/.git" ]]; then
    # Match the exact repo (HTTPS or SSH, with or without .git suffix) so
    # forks like 'vue-starter-kit-fork' don't pass the check.
    existing=$(git -C "$dest" remote get-url origin 2>/dev/null || true)
    if [[ ! "$existing" =~ ^(https://github\.com/|git@github\.com:)laravel/${kit}(\.git)?$ ]]; then
        echo "ERROR: '$dest' exists but is not a clone of laravel/$kit (origin: ${existing:-none})" >&2
        exit 4
    fi

    git -C "$dest" fetch --quiet --depth 500 origin "$branch"
    git -C "$dest" checkout --quiet "origin/$branch"
else
    git clone --quiet --depth 500 --branch "$branch" "$url" "$dest"
fi

echo "$dest"
