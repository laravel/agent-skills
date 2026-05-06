#!/usr/bin/env bash
# scan_transitive_imports.sh — scan applied `new` files for imports that
# may point at helpers absent in the user's repo.
#
# Usage: scan_transitive_imports.sh <kit> <new_files...>
#   <kit>  one of: vue-starter-kit, react-starter-kit, svelte-starter-kit, livewire-starter-kit
#
# Vue / React / Svelte: TS/JS imports with @, ~, ./, ../ aliases.
# Livewire: Blade includes, x-components, livewire tags.
#
# Output mirrors `grep -EHn` so the agent sees `<file>:<line>:<match>` for
# every import. Empty output means no transitive imports to chase. Always
# exits 0 — finding nothing is not an error.

set -euo pipefail

usage() {
    echo "Usage: $0 <kit> <new_files...>" >&2
    exit 2
}

[[ $# -lt 2 ]] && usage

kit="$1"; shift

# Pick the import-style regex for the kit. Same DRY shape as run_tests.sh's
# discover_* helpers: each kit maps to one canonical pattern.
case "$kit" in
    vue-starter-kit|react-starter-kit|svelte-starter-kit)
        pattern="from ['\"](@/|~/|\\./|\\.\\./)"
        ;;
    livewire-starter-kit)
        pattern="@(include|extends|component|livewire)\\(|<x-|<livewire:"
        ;;
    *)
        echo "ERROR: unknown kit '$kit'" >&2
        exit 3
        ;;
esac

grep -EHn "$pattern" "$@" 2>/dev/null || true
