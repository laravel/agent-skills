#!/usr/bin/env bash
# cumulative_bleed.sh — for the files a feature commit touches, list which
# of those files have ALSO been modified by later upstream commits.
#
# Usage: cumulative_bleed.sh <kit_dir> <sha> <user_repo>
#
# Output: one path per line. If the list is non-empty, copying upstream
# HEAD's content for those paths will pull in changes beyond the feature.
# In that case, scope to <sha>:<path> instead of HEAD:<path> when applying.

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

paths=$("$script_dir/classify_feature.sh" "$kit_dir" "$sha" "$user_repo" | cut -f2)
[[ -z "$paths" ]] && exit 0

git -C "$kit_dir" log --name-only --pretty=format: "${sha}..HEAD" -- $paths \
    | sort -u \
    | sed '/^$/d'
