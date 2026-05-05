#!/usr/bin/env bash
# run_tests.sh — discover and run the user's verification commands, optionally
# comparing pre-upgrade and post-upgrade results so we don't blame the upgrade
# for failures that already existed.
#
# Usage:
#   run_tests.sh <user_repo>                          # run, print summary, exit 0/1
#   run_tests.sh <user_repo> --baseline <out.json>    # record results to out.json
#   run_tests.sh <user_repo> --compare  <baseline.json>  # compare to baseline
#
# Discovery (per category, first match wins):
#   php_tests:    composer.json scripts.test → vendor/bin/pest → vendor/bin/phpunit → php artisan test
#   js_typecheck: package.json scripts.types → scripts.typecheck → scripts.tsc
#   js_build:     package.json scripts.build
#
# All three checks run in parallel. Each check's combined stdout+stderr is
# captured to /tmp/skup-tests-<label>.log so failures can be surfaced.
#
# Results JSON shape (built and parsed with jq — never with grep/sed):
#   {
#     "php_tests":    {"ran": true,  "command": "vendor/bin/pest", "passed": true,  "exit": 0, "log": "/tmp/..."},
#     "js_typecheck": {"ran": false, "reason": "no command discovered"},
#     "js_build":     {"ran": true,  "command": "pnpm run build", "passed": false, "exit": 1, "log": "/tmp/..."}
#   }
#
# Compare mode: prints regressions only — labels that passed in baseline and now fail.

set -uo pipefail

usage() {
    echo "Usage: $0 <user_repo> [--baseline <out.json> | --compare <baseline.json>]" >&2
    exit 2
}

[[ $# -lt 1 ]] && usage
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 3; }

repo="$1"; shift
mode="run"
ref=""

case "${1:-}" in
    "")            mode="run" ;;
    --baseline)    mode="baseline"; ref="${2:-}"; [[ -z "$ref" ]] && usage ;;
    --compare)     mode="compare";  ref="${2:-}"; [[ -z "$ref" ]] && usage ;;
    *)             usage ;;
esac

cd "$repo"

# Pick the JS package manager; only meaningful when package.json exists.
js_package_manager() {
    [[ -f package.json ]] || return 1
    if [[ -f pnpm-lock.yaml ]]; then echo pnpm
    elif [[ -f bun.lockb || -f bun.lock ]]; then echo bun
    elif [[ -f yarn.lock ]]; then echo yarn
    else echo npm
    fi
}

has_npm_script() {
    [[ -f package.json ]] || return 1
    jq -e --arg s "$1" '.scripts[$s] // empty' package.json >/dev/null 2>&1
}

# Each discover_* prints the discovered command (one line, command + args)
# or nothing if no command exists for that category.
discover_php_tests() {
    if [[ -f composer.json ]] && jq -e '.scripts.test // empty' composer.json >/dev/null 2>&1; then
        echo "composer test"
    elif [[ -x vendor/bin/pest ]]; then echo "vendor/bin/pest"
    elif [[ -x vendor/bin/phpunit ]]; then echo "vendor/bin/phpunit"
    elif [[ -f artisan ]]; then echo "php artisan test"
    fi
}

discover_js_typecheck() {
    local pm; pm=$(js_package_manager) || return 0

    for s in types typecheck tsc; do
        if has_npm_script "$s"; then echo "$pm run $s"; return; fi
    done
}

discover_js_build() {
    local pm; pm=$(js_package_manager) || return 0

    has_npm_script build && echo "$pm run build"
}

# Run a single check in the background. Writes one JSON object to <out_json>.
# stdout+stderr go to /tmp/skup-tests-<label>.log for later surfacing.
run_check() {
    local label="$1" cmd="$2" out_json="$3"
    local logfile="/tmp/skup-tests-${label}.log"

    if [[ -z "$cmd" ]]; then
        jq -nc --arg l "$label" '{($l): {ran: false, reason: "no command discovered"}}' > "$out_json"
        return
    fi

    : > "$logfile"
    bash -c "$cmd" >"$logfile" 2>&1
    local ec=$?
    jq -nc --arg l "$label" --arg c "$cmd" --arg log "$logfile" --argjson ec "$ec" \
        '{($l): {ran: true, command: $c, passed: ($ec == 0), exit: $ec, log: $log}}' > "$out_json"
}

# Run all three checks in parallel and merge their result fragments.
build_results() {
    local php js_t js_b
    php=$(discover_php_tests)
    js_t=$(discover_js_typecheck)
    js_b=$(discover_js_build)

    local f1 f2 f3
    f1=$(mktemp); f2=$(mktemp); f3=$(mktemp)

    run_check php_tests    "$php"  "$f1" &
    run_check js_typecheck "$js_t" "$f2" &
    run_check js_build     "$js_b" "$f3" &
    wait

    jq -s 'add' "$f1" "$f2" "$f3"
    rm -f "$f1" "$f2" "$f3"
}

case "$mode" in
    run)
        results=$(build_results)
        echo "$results"

        # Exit 1 if anything that ran failed.
        if [[ $(echo "$results" | jq '[.. | objects | select(.passed == false)] | length') -gt 0 ]]; then
            exit 1
        fi
        ;;

    baseline)
        build_results > "$ref"
        echo "baseline recorded: $ref" >&2
        ;;

    compare)
        [[ -f "$ref" ]] || { echo "ERROR: baseline '$ref' not found" >&2; exit 2; }

        post=$(build_results)
        regressed=0

        for label in php_tests js_typecheck js_build; do
            was_pass=$(jq -r --arg l "$label" '.[$l].passed == true' "$ref")
            is_fail=$(echo "$post" | jq -r --arg l "$label" '.[$l].passed == false')
            if [[ "$was_pass" == "true" ]] && [[ "$is_fail" == "true" ]]; then
                logfile=$(echo "$post" | jq -r --arg l "$label" '.[$l].log // ""')
                echo "REGRESSION: $label was passing, now fails (log: $logfile)" >&2
                regressed=1
            fi
        done

        echo "$post"
        exit $regressed
        ;;
esac
