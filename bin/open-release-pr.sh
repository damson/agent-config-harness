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

# Merge subjects name the PR they closed: "Merge pull request #41 from ...".
pr_list=$(git log "$range" --merges --format='%s' \
          | sed -nE 's|^Merge pull request #([0-9]+) from .*|#\1|p' \
          | paste -sd' ' -)
[ -n "$pr_list" ] || pr_list="(none — direct commits only)"

subjects=$(git log "$range" --no-merges --format='- %s' | head -40)
stat=$(git diff --shortstat "origin/$BASE" "origin/$HEAD")
[ -n "$stat" ] || stat="(no file changes)"
oldest=$(git log "$range" --format='%ad' --date=short | tail -1)

template="$HARNESS_ROOT/config/templates/pr/release.md"
[ -f "$template" ] || log_error "Missing release template: $template"

body=$(cat <<BODY
$(cat "$template")

---

## 📦 What is in this batch

*Assembled by \`bin/open-release-pr.sh\`. The sections above need a human — this
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

if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "$body"
    exit 0
fi

existing=$(gh pr list --base "$BASE" --head "$HEAD" --state open --json number \
           --jq '.[0].number // empty')

if [ -n "$existing" ]; then
    log_info "Refreshing release PR #$existing ($count commits)"
    gh pr edit "$existing" --body "$body"
    log_ok "Updated #$existing"
else
    log_info "Opening a release PR ($count commits)"
    gh pr create --base "$BASE" --head "$HEAD" \
        --title "release: $count commits from $HEAD" \
        --body "$body"
    log_ok "Release PR opened — fill in the summary and the before/after diagram."
fi
