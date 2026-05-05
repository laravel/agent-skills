#!/usr/bin/env bash
# run_tests.sh — discover and run the user's verification commands, optionally
# comparing pre-upgrade and post-upgrade results so we don't blame the upgrade
# for failures that already existed.
#
# Usage:
#   run_tests.sh <user_repo>                       # run, print summary, exit 0/1
#   run_tests.sh <user_repo> --baseline <out.json> # record results to out.json
#   run_tests.sh <user_repo> --compare <baseline.json>  # compare to recorded baseline
#
# Each verification command is one of: php tests, JS typecheck, JS build.
# Discovery order, per category:
#
#   php tests:   composer.json scripts.test → vendor/bin/pest → vendor/bin/phpunit → php artisan test
#   js typecheck: package.json scripts.types → scripts.typecheck → scripts.tsc
#   js build:    package.json scripts.build
#
# Results JSON shape:
#   { "php_tests":   { "ran": true,  "command": "...", "passed": true,  "exit": 0 },
#     "js_typecheck":{ "ran": false, "reason": "no script" },
#     "js_build":    { "ran": true,  "command": "...", "passed": false, "exit": 1 } }
#
# Compare mode prints regressions only — checks that passed before and now fail.

set -uo pipefail

repo="${1:-.}"
mode="run"
ref=""
if [[ "${2:-}" == "--baseline" ]]; then mode="baseline"; ref="${3:-}"; fi
if [[ "${2:-}" == "--compare" ]];  then mode="compare";  ref="${3:-}"; fi

cd "$repo"

# Pick the JS package manager based on existing lockfile
js_pm() {
    if [[ -f pnpm-lock.yaml ]]; then echo pnpm
    elif [[ -f bun.lockb ]] || [[ -f bun.lock ]]; then echo bun
    elif [[ -f yarn.lock ]]; then echo yarn
    elif [[ -f package-lock.json ]]; then echo npm
    else echo npm
    fi
}

has_npm_script() {
    [[ -f package.json ]] || return 1
    grep -Eq "\"$1\"[[:space:]]*:" package.json
}

# Returns: command on stdout if discoverable, empty otherwise
discover_php_tests() {
    if [[ -f composer.json ]] && grep -Eq '"test"[[:space:]]*:' composer.json; then
        echo "composer test"; return
    fi
    [[ -x vendor/bin/pest ]]    && { echo "vendor/bin/pest"; return; }
    [[ -x vendor/bin/phpunit ]] && { echo "vendor/bin/phpunit"; return; }
    [[ -f artisan ]]            && { echo "php artisan test"; return; }
    echo ""
}

discover_js_typecheck() {
    local pm; pm="$(js_pm)"
    for s in types typecheck tsc; do
        if has_npm_script "$s"; then echo "$pm run $s"; return; fi
    done
    echo ""
}

discover_js_build() {
    local pm; pm="$(js_pm)"
    has_npm_script build && { echo "$pm run build"; return; }
    echo ""
}

run_check() {
    local label="$1" cmd="$2"
    if [[ -z "$cmd" ]]; then
        printf '  "%s": {"ran": false, "reason": "no command discovered"},\n' "$label"
        return
    fi
    echo "==> [$label] $cmd" >&2
    eval "$cmd" >/dev/null 2>&1
    local ec=$?
    if [[ $ec -eq 0 ]]; then
        printf '  "%s": {"ran": true, "command": "%s", "passed": true, "exit": 0},\n' "$label" "$cmd"
    else
        printf '  "%s": {"ran": true, "command": "%s", "passed": false, "exit": %d},\n' "$label" "$cmd" "$ec"
    fi
}

# Build the result JSON
build_results() {
    local php js_t js_b
    php="$(discover_php_tests)"
    js_t="$(discover_js_typecheck)"
    js_b="$(discover_js_build)"
    {
        echo "{"
        run_check php_tests    "$php"
        run_check js_typecheck "$js_t"
        run_check js_build     "$js_b"
        # Trim trailing comma from last line and close
    } | sed -e '$ s/},$/}/' \
       | { cat; echo "}"; }
}

case "$mode" in
    run)
        results="$(build_results)"
        echo "$results"
        # Non-zero if any check that ran failed
        if echo "$results" | grep -q '"passed": false'; then exit 1; fi
        exit 0
        ;;
    baseline)
        [[ -z "$ref" ]] && { echo "ERROR: --baseline needs an output path" >&2; exit 2; }
        build_results > "$ref"
        echo "baseline recorded: $ref" >&2
        ;;
    compare)
        [[ -z "$ref" ]] && { echo "ERROR: --compare needs a baseline file" >&2; exit 2; }
        [[ -f "$ref" ]] || { echo "ERROR: baseline '$ref' not found" >&2; exit 2; }
        post="$(build_results)"
        # Regressions: any check passed=true in baseline AND passed=false now.
        regressed=0
        # Each label has its full status on a single line in the JSON, so match per-line.
        for label in php_tests js_typecheck js_build; do
            was_pass=$(grep "\"$label\":" "$ref"        | grep -c '"passed": true'  || true)
            is_fail=$( echo "$post" | grep "\"$label\":" | grep -c '"passed": false' || true)
            if [[ "$was_pass" -gt 0 ]] && [[ "$is_fail" -gt 0 ]]; then
                echo "REGRESSION: $label was passing, now fails" >&2
                regressed=1
            fi
        done
        echo "$post"
        exit $regressed
        ;;
esac
