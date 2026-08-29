#!/usr/bin/env bash
#
# AI Setup — open (or refresh) the PR that brings main back into develop.
#
# Merging develop into main leaves a merge commit on main that develop never
# sees. One release, one commit of drift — and it accumulates silently, because
# the trees stay identical, so nothing you can see in a working copy is wrong.
# Five releases in, `git rev-list --count origin/develop..origin/main` answered
# 5 while `git diff origin/develop origin/main` was empty. Anything that asks
# "is this branch behind?" answered yes about a branch missing nothing.
#
# It never merges, for the same reason the release script does not: a merge
# into a protected branch stays a human decision. What it removes is having to
# remember, which is the part that had never worked.
#
# Usage:
#   ./bin/open-backmerge-pr.sh            # create or refresh
#   ./bin/open-backmerge-pr.sh --dry-run  # print the body, touch nothing
#
# Env:
#   BACKMERGE_BASE (default develop), BACKMERGE_HEAD (default main)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

BASE="${BACKMERGE_BASE:-develop}"
HEAD="${BACKMERGE_HEAD:-main}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

require git "install git"
[ "$DRY_RUN" -eq 1 ] || require gh "brew install gh"

git fetch origin --quiet "$BASE" "$HEAD" 2>/dev/null || true

range="origin/$BASE..origin/$HEAD"
count=$(git rev-list --count "$range")

if [ "$count" -eq 0 ]; then
    log_info "$BASE is level with $HEAD — nothing to back-merge."
    exit 0
fi

subjects=$(git log "$range" --format='- %s' | head -40)

# The distinction that decides how much review this needs. A plain back-merge
# after a release carries merge commits and no file changes. Anything else means
# something landed on $HEAD directly — a hotfix — and the diff is real.
stat=$(git diff --shortstat "origin/$BASE" "origin/$HEAD")
if [ -n "$stat" ]; then
    nature="**Carries file changes** — \`$stat\`. Something landed on \`$HEAD\` without going through \`$BASE\`; review this as a normal change, not as a formality."
else
    nature="**History only.** \`git diff origin/$BASE origin/$HEAD\` is empty — the trees are byte-identical and no file can change. This PR carries merge commits and nothing else."
fi

body=$(cat <<BODY
## 👥 In plain words

Releases move code one way, from the integration branch to the release branch. Each one leaves a merge commit behind on the release branch that the integration branch never receives. Nothing about the files differs, so nothing looks wrong, but the two branches drift a commit further apart every time — and tools that ask whether a branch is behind start answering yes about a branch that is missing nothing.

This brings them level again.

## 📋 What changed

$nature

<details>
<summary>Commits being brought back ($count)</summary>

$subjects

</details>

## ✅ Test plan

<!--
    Tick what you checked. For a history-only back-merge the first box is the
    whole test plan: if the trees are identical, no file can change, and a
    suite run proves nothing a diff has not already proven.
-->

- [ ] \`git diff origin/$BASE origin/$HEAD\` reviewed — empty for a routine back-merge
- [ ] If it carries file changes: suite run on the merge result

## 🤖 Review

- [ ] Nothing is authored here — this PR moves existing commits only

---

*Opened by \`bin/open-backmerge-pr.sh\`.*
BODY
)

if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "$body"
    exit 0
fi

existing=$(gh pr list --base "$BASE" --head "$HEAD" --state open --json number \
           --jq '.[0].number // empty')

if [ -n "$existing" ]; then
    log_info "Refreshing back-merge PR #$existing ($count commits)"
    gh pr edit "$existing" --body "$body"
    log_ok "Updated #$existing"
else
    log_info "Opening a back-merge PR ($count commits)"
    gh pr create --base "$BASE" --head "$HEAD" \
        --title "Bring $HEAD back into $BASE" \
        --body "$body"
    log_ok "Back-merge PR opened — merge it to bring $BASE level."
fi
