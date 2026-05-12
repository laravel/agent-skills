#!/usr/bin/env bash
# reconcile_manifests.sh — regenerate composer.lock and the JS lockfile
# after the user has merged manifest changes from upstream.
#
# Usage: reconcile_manifests.sh <user_repo>
#
# - Runs `composer install` if composer.json + composer.lock both exist.
# - Auto-detects the JS package manager from the existing lockfile and runs
#   `<pm> install`. On install failure (often ERESOLVE after a major bump),
#   removes node_modules and the lockfile, then reinstalls. The recovery is
#   announced on stderr so the agent can include it in the report.
#
# The user must have already agreed to run this — the script doesn't ask.

set -euo pipefail

usage() {
    echo "Usage: $0 <user_repo>" >&2
    exit 2
}

[[ $# -lt 1 ]] && usage

repo="$1"
cd "$repo"

# Mirror run_tests.sh's auto-detection. Both helpers return non-zero (via
# the `[[ -f package.json ]] || return 1` guard) when the project has no
# package.json, so callers must guard their use behind that check.
js_package_manager() {
    [[ -f package.json ]] || return 1

    if   [[ -f pnpm-lock.yaml ]];           then echo pnpm
    elif [[ -f bun.lockb || -f bun.lock ]]; then echo bun
    elif [[ -f yarn.lock ]];                then echo yarn
    else                                         echo npm
    fi
}

js_lockfile() {
    [[ -f package.json ]] || return 1

    if   [[ -f pnpm-lock.yaml ]]; then echo pnpm-lock.yaml
    elif [[ -f bun.lockb ]];      then echo bun.lockb
    elif [[ -f bun.lock ]];       then echo bun.lock
    elif [[ -f yarn.lock ]];      then echo yarn.lock
    else                               echo package-lock.json
    fi
}

if [[ -f composer.json && -f composer.lock ]]; then
    echo "==> composer install --no-interaction" >&2
    composer install --no-interaction
fi

if [[ -f package.json ]]; then
    pm=$(js_package_manager)
    lock=$(js_lockfile)

    echo "==> $pm install" >&2
    if ! "$pm" install; then
        # Common cause: stale node_modules after a major bump (ERESOLVE).
        # Try the standard recovery once before giving up.
        echo "==> '$pm install' failed; removing node_modules + $lock and retrying" >&2
        rm -rf node_modules "$lock"
        "$pm" install
    fi
fi
