#!/usr/bin/env bash
#
# AI Setup — open (or refresh) the release PR that promotes develop to main.
#
# Releases had been drifting: the last one left main 39 commits and eight PRs
# behind, which makes the promotion a big-bang review and delays every
# `closes #N` keyword, since GitHub only honours those on a merge into the
# default branch. A standing PR keeps the batch small and visible.
#
# It never merges. It opens a PR pre-filled with the inventory a human cannot
# be bothered to assemble — the PRs in the batch, the diffstat, the commit
# count — and leaves the parts that need judgement (the high-level summary and
# the before/after diagram) as an unfilled template.
#
# Usage:
#   ./bin/open-release-pr.sh            # create or refresh
#   ./bin/open-release-pr.sh --dry-run  # print the body, touch nothing
#
# Env:
#   RELEASE_BASE (default main), RELEASE_HEAD (default develop)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

BASE="${RELEASE_BASE:-main}"
HEAD="${RELEASE_HEAD:-develop}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

require git "install git"
[ "$DRY_RUN" -eq 1 ] || require gh "brew install gh"

git fetch origin --quiet "$BASE" "$HEAD" 2>/dev/null || true

range="origin/$BASE..origin/$HEAD"
count=$(git rev-list --count "$range")

if [ "$count" -eq 0 ]; then
    log_info "$HEAD is not ahead of $BASE — nothing to release."
    exit 0
fi

# Subjects name the PR they closed two ways: a merge commit reads
# "Merge pull request #41 from ...", a squash commit ends in "... (#41)".
pr_list=$(git log "$range" --format='%s' \
          | sed -nE -e 's|^Merge pull request #([0-9]+) from .*|#\1|p' \
                    -e 's|.* \(#([0-9]+)\)$|#\1|p' \
          | awk '!seen[$0]++' \
          | paste -sd' ' -)
[ -n "$pr_list" ] || pr_list="(none, direct commits only)"

subjects=$(git log "$range" --no-merges --format='- %s' | head -40)
stat=$(git diff --shortstat "origin/$BASE" "origin/$HEAD")
[ -n "$stat" ] || stat="(no file changes)"
oldest=$(git log "$range" --format='%ad' --date=short | tail -1)

template="$HARNESS_ROOT/config/templates/pr/release.md"
[ -f "$template" ] || log_error "Missing release template: $template"

# The heading the generated block starts at. Everything above it belongs to
# whoever wrote it; everything from it down is reassembled on every run.
MARKER='## 📦 What is in this batch'

inventory=$(cat <<BODY
$MARKER

*Assembled by \`bin/open-release-pr.sh\`. The sections above need a human; this
one does not.*

| | |
|---|---|
| Commits | $count |
| Pull requests | $pr_list |
| Oldest unreleased commit | $oldest |
| Diff | $stat |

<details>
<summary>Commit subjects</summary>

$subjects

</details>
BODY
)

# Everything a human wrote, which is every line above the marker: the summary
# and the before/after diagram a release must carry. Refreshing used to
# regenerate the whole body and discard both, silently. That was survivable
# weekly and is not now the refresh runs on every push to the integration
# branch. A body with no marker in it is kept whole rather than guessed at.
human_prefix() {
    awk -v m="$MARKER" '
        # kcov-ignore-start
        index($0, m) == 1 { exit }
        { line[NR] = $0; last = NR }
        END {
            # Drop the trailing rule and blank lines, so rejoining is
            # idempotent rather than growing a separator per refresh.
            while (last > 0 && (line[last] ~ /^[[:space:]]*$/ || line[last] ~ /^---[[:space:]]*$/))
                last--
            for (i = 1; i <= last; i++) print line[i]
        }
    '
    # kcov-ignore-end
}

assemble() {
    printf '%s\n\n---\n\n%s\n' "$1" "$inventory"
}

if [ "$DRY_RUN" -eq 1 ]; then
    assemble "$(cat "$template")"
    exit 0
fi

existing=$(gh pr list --base "$BASE" --head "$HEAD" --state open --json number \
           --jq '.[0].number // empty')

if [ -n "$existing" ]; then
    log_info "Refreshing release PR #$existing ($count commits)"
    kept=$(gh pr view "$existing" --json body --jq .body | human_prefix)
    [ -n "$kept" ] || kept=$(cat "$template")
    gh pr edit "$existing" --body "$(assemble "$kept")"
    log_ok "Updated #$existing"
else
    log_info "Opening a release PR ($count commits)"
    gh pr create --base "$BASE" --head "$HEAD" \
        --title "release: $count commits from $HEAD" \
        --body "$(assemble "$(cat "$template")")"
    log_ok "Release PR opened — fill in the summary and the before/after diagram."
fi
