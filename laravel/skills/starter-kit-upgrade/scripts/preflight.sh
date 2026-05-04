#!/usr/bin/env bash
# preflight.sh — verify the user's repo is in a state where it's safe to operate.
#
# Usage: preflight.sh [user_repo]   (defaults to current dir)
# Exit codes:
#   0  ok
#   1  not a git repo
#   2  working tree dirty
#   3  gh missing
#   4  gh not authenticated

set -euo pipefail

repo="${1:-.}"

if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: '$repo' is not a git repository." >&2
    echo "This skill requires a git repo so changes can be committed and reverted." >&2
    exit 1
fi

if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
    echo "ERROR: working tree is not clean." >&2
    echo "Commit or stash your changes before running this skill." >&2
    echo "" >&2
    git -C "$repo" status --short >&2
    exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: 'gh' (GitHub CLI) is not installed." >&2
    echo "Install it from https://cli.github.com and run 'gh auth login'." >&2
    exit 3
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: 'gh' is not authenticated." >&2
    echo "Run 'gh auth login' before using this skill." >&2
    exit 4
fi

echo "preflight: OK"
