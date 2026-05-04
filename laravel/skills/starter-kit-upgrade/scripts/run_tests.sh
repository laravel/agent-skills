#!/usr/bin/env bash
# run_tests.sh — discover and run the user's test command.
#
# Usage: run_tests.sh [user_repo]   (defaults to current dir)
#
# Discovery order:
#   1. composer.json scripts.test (preferred — user-defined)
#   2. vendor/bin/pest
#   3. vendor/bin/phpunit
#   4. php artisan test
#
# Prints the discovered command before running, so the agent can report
# what was executed. Exits with the test runner's exit code.

set -euo pipefail

repo="${1:-.}"
cd "$repo"

run() {
    echo "run_tests: $*" >&2
    "$@"
}

if [[ -f composer.json ]] && grep -q '"test"[[:space:]]*:' composer.json 2>/dev/null; then
    run composer test
    exit $?
fi

if [[ -x vendor/bin/pest ]]; then
    run vendor/bin/pest
    exit $?
fi

if [[ -x vendor/bin/phpunit ]]; then
    run vendor/bin/phpunit
    exit $?
fi

if [[ -f artisan ]]; then
    run php artisan test
    exit $?
fi

echo "ERROR: could not discover a test command." >&2
echo "Looked for: composer.json scripts.test, vendor/bin/pest, vendor/bin/phpunit, artisan." >&2
exit 1
