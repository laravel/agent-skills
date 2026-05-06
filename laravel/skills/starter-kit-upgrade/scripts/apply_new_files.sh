#!/usr/bin/env bash
# apply_new_files.sh — write upstream HEAD's content for every file the
# classifier reports as `new`, and stage each.
#
# Usage: apply_new_files.sh <kit_dir> <sha> <user_repo>
#
# Files with any other classifier status (already-present, differs,
# deleted-upstream, lockfile) are left alone for the agent to handle
# interactively per Phase 5 step 5.
#
# Prints "applied <path>" for each file written so the caller can include
# the list in the feature commit message and the report.

set -euo pipefail

usage() {
    echo "Usage: $0 <kit_dir> <sha> <user_repo>" >&2
    exit 2
}

[[ $# -lt 3 ]] && usage

kit_dir="$1"
sha="$2"
user_repo="$3"

script_dir="$(cd "$(dirname "$0")" && pwd)"

"$script_dir/classify_feature.sh" "$kit_dir" "$sha" "$user_repo" \
    | awk -F'\t' '$1=="new"{print $2}' \
    | while IFS= read -r path; do
        mkdir -p "$user_repo/$(dirname "$path")"
        git -C "$kit_dir" show "HEAD:$path" > "$user_repo/$path"
        git -C "$user_repo" add -- "$path"
        echo "applied $path"
      done
