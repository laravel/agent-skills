#!/usr/bin/env bash
# apply_feature.sh — apply only the safe-by-default parts of an upstream feature.
#
# Usage: apply_feature.sh <kit_dir> <sha> <user_repo>
#
# What gets applied automatically:
#   new              create file from upstream's current content
#
# What gets skipped (and reported on stdout for the agent to handle):
#   already-present  no action needed
#   differs          requires explicit user decision; agent walks the user through
#                    each one (take upstream / keep theirs / merge by hand)
#   lockfile         user-mediated; agent walks through manifest changes
#
# This script never silently combines the user's edits with upstream's edits.
# It only ever creates files the user does not have. Anything the user has
# already authored is left untouched here — by design.
#
# Stages applied changes with `git add`. Does NOT commit — caller decides the
# commit shape (typically one commit per feature, made by the agent after the
# `differs` files have been resolved with the user).
#
# Output format (one line per file): "<action>\t<status>\t<path>"
#   action is "applied" or "skipped"

set -euo pipefail

kit_dir="$1"
sha="$2"
user_repo="$3"

script_dir="$(cd "$(dirname "$0")" && pwd)"

upstream_current() {
    git -C "$kit_dir" show "HEAD:$1" 2>/dev/null || true
}

while IFS=$'\t' read -r status path; do
    [[ -z "${status:-}" ]] && continue
    case "$status" in
        new)
            mkdir -p "$user_repo/$(dirname "$path")"
            upstream_current "$path" > "$user_repo/$path"
            git -C "$user_repo" add -- "$path"
            printf "applied\t%s\t%s\n" "$status" "$path"
            ;;
        already-present|differs|lockfile)
            printf "skipped\t%s\t%s\n" "$status" "$path"
            ;;
        *)
            printf "skipped\tunknown(%s)\t%s\n" "$status" "$path"
            ;;
    esac
done < <("$script_dir/classify_feature.sh" "$kit_dir" "$sha" "$user_repo")
