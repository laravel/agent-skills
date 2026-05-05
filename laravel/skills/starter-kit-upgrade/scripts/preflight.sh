#!/usr/bin/env bash
# preflight.sh — verify the user's repo is in a state where the skill can
# safely operate. Run before any side effects.
#
# Usage: preflight.sh <user_repo>
#
# Checks (in order):
#   1. Path is a git repo
#   2. Working tree is clean (no uncommitted changes)
#   3. `gh` is available and authenticated
#   4. `jq` is available
#
# Exits non-zero with a clear message about which check failed and how to fix.
# Exit codes are stable so the agent can branch on them if needed:
#   2 = not a git repo
#   3 = dirty working tree
#   4 = gh missing
#   5 = gh not authenticated
#   6 = jq missing

set -euo pipefail

usage() {
    echo "Usage: $0 <user_repo>" >&2
    exit 2
}

[[ $# -lt 1 ]] && usage

repo="$1"

fail() {
    local code="$1" message="$2" hint="$3"

    echo "FAIL: $message" >&2
    echo "$hint" >&2

    exit "$code"
}

check_git_repo() {
    git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || fail 2 "'$repo' is not a git repository." \
                  "Run 'git init' (or pass a path inside an existing repo)."
}

check_clean_tree() {
    [[ -z "$(git -C "$repo" status --porcelain)" ]] && return

    echo "FAIL: '$repo' has uncommitted changes." >&2
    echo "Commit or stash them before running this skill." >&2
    git -C "$repo" status --short >&2

    exit 3
}

check_gh_installed() {
    command -v gh >/dev/null 2>&1 \
        || fail 4 "'gh' CLI is not installed." \
                  "Install: https://cli.github.com/"
}

check_gh_authenticated() {
    gh auth status >/dev/null 2>&1 \
        || fail 5 "'gh' is not authenticated." \
                  "Run: gh auth login"
}

check_jq_installed() {
    command -v jq >/dev/null 2>&1 \
        || fail 6 "'jq' is not installed." \
                  "Install via your package manager (e.g. 'brew install jq')."
}

check_git_repo
check_clean_tree
check_gh_installed
check_gh_authenticated
check_jq_installed

echo "preflight: OK"
