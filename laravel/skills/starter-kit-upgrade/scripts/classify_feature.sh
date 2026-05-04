#!/usr/bin/env bash
# classify_feature.sh — classify each file touched by an upstream feature commit
# against the user's repo, comparing only against upstream's current branch tip.
#
# Usage: classify_feature.sh <kit_dir> <sha> <user_repo>
#
# The SHA is used only to enumerate which files the feature touches.
# Comparison is always against upstream's current state (HEAD of the branch
# already checked out in <kit_dir> by fetch_kit.sh) — never against the
# commit's parent. The user's git history is unrelated to the kit's history,
# so "what was the file before the change" is not a meaningful concept on
# their side.
#
# Per file, prints one TAB-separated line:
#   <status>\t<path>
#
# Statuses:
#   new              file does not exist in user repo and exists upstream
#   already-present  user file is byte-identical to upstream's current file
#                    (or both upstream and user lack the file)
#   differs          user has the file but content differs from upstream's current
#                    (also the case for files upstream has deleted but user kept)
#   lockfile         composer/package manifest or lockfile (user-mediated only)
#
# All comparisons are byte-exact via diff(1).

set -euo pipefail

kit_dir="$1"
sha="$2"
user_repo="$3"

is_lockfile() {
    case "$1" in
        composer.json|composer.lock|package.json|package-lock.json|pnpm-lock.yaml|yarn.lock)
            return 0 ;;
        *) return 1 ;;
    esac
}

# Returns 0 if the path exists at HEAD in the kit, 1 if not.
upstream_has() {
    git -C "$kit_dir" cat-file -e "HEAD:$1" 2>/dev/null
}

# Stream upstream's current file content to stdout (empty if missing).
upstream_current() {
    git -C "$kit_dir" show "HEAD:$1" 2>/dev/null || true
}

classify_one() {
    local path="$1"
    local user_file="$user_repo/$path"

    if is_lockfile "$path"; then
        printf "lockfile\t%s\n" "$path"
        return
    fi

    if upstream_has "$path"; then
        if [[ -e "$user_file" ]]; then
            if upstream_current "$path" | diff -q - "$user_file" >/dev/null 2>&1; then
                printf "already-present\t%s\n" "$path"
            else
                printf "differs\t%s\n" "$path"
            fi
        else
            printf "new\t%s\n" "$path"
        fi
    else
        # Upstream no longer has this file at the branch tip
        if [[ -e "$user_file" ]]; then
            # User still has it — surface (could be intentional kept or deletion candidate)
            printf "differs\t%s\n" "$path"
        else
            printf "already-present\t%s\n" "$path"
        fi
    fi
}

# Use the feature commit only to enumerate which paths to look at.
git -C "$kit_dir" diff-tree --no-commit-id --name-only --no-renames -r "$sha" \
    | while IFS= read -r path; do
        [[ -z "${path:-}" ]] && continue
        classify_one "$path"
    done
