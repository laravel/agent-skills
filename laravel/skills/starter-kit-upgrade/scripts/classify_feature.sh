#!/usr/bin/env bash
# classify_feature.sh — classify each file touched by an upstream feature commit
# against the user's repo, comparing only against upstream's current branch tip.
#
# Usage: classify_feature.sh <kit_dir> <sha> <user_repo>
#
# The SHA enumerates which files the feature touches. Comparison is always
# against upstream HEAD (already checked out in <kit_dir>). The user's git
# history is unrelated to the kit's, so "what was the file before the change"
# is not meaningful on their side.
#
# Per file, prints "<status>\t<path>". Statuses:
#   new                 absent in user repo, exists at upstream HEAD
#   already-present     user's bytes equal upstream HEAD's bytes
#   differs             user has the file but bytes differ from upstream HEAD
#   deleted-upstream    upstream HEAD lacks the file but the user still has it
#   lockfile            composer/package manifest or lockfile (always user-mediated)
#
# All comparisons are byte-exact via diff(1).

set -euo pipefail

kit_dir="$1"
sha="$2"
user_repo="$3"

classify() {
    local path="$1"
    local user_file="$user_repo/$path"

    case "$path" in
        composer.json|composer.lock|package.json|package-lock.json|pnpm-lock.yaml|yarn.lock|bun.lockb|bun.lock)
            printf "lockfile\t%s\n" "$path"
            return
            ;;
    esac

    local upstream
    upstream=$(mktemp)

    # Single call: succeeds iff upstream has the file. No separate existence check.
    if git -C "$kit_dir" show "HEAD:$path" >"$upstream" 2>/dev/null; then
        if [[ -e "$user_file" ]]; then
            if diff -q "$upstream" "$user_file" >/dev/null 2>&1; then
                printf "already-present\t%s\n" "$path"
            else
                printf "differs\t%s\n" "$path"
            fi
        else
            printf "new\t%s\n" "$path"
        fi
    else
        # Upstream HEAD doesn't have this path — only meaningful if the user still does.
        if [[ -e "$user_file" ]]; then
            printf "deleted-upstream\t%s\n" "$path"
        else
            printf "already-present\t%s\n" "$path"
        fi
    fi

    rm -f "$upstream"
}

# diff-tree gives us the paths the feature touched; classification is against HEAD.
git -C "$kit_dir" diff-tree --no-commit-id --name-only --no-renames -r "$sha" \
    | while IFS= read -r path; do
        [[ -z "${path:-}" ]] && continue
        classify "$path"
    done
