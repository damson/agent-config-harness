#!/usr/bin/env bash
#
# AI Setup — bring develop level with main after a release.
#
# A release merges develop into main and leaves a merge commit on main that
# develop never receives. The trees stay byte-identical, so nothing in a working
# copy looks wrong and only a commit count reveals it: five releases in,
# `git rev-list --count origin/develop..origin/main` answered 5 while
# `git diff origin/develop origin/main` was empty. Anything that asks whether a
# branch is behind answered yes about a branch missing nothing.
#
# Every back-merge this repo has done was a pure fast-forward carrying an empty
# diff, and it used to be delivered by a pull request nobody could review: no
# diff to read, no CI worth running, and, because a workflow opened it with
# GITHUB_TOKEN, two workflow runs per release that GitHub held for approval,
# never ran, and finally recorded as failures. A fast-forward is a push, so this
# does the push. A pull request is kept for the one shape that actually needs
# one: when develop has moved on and a real merge commit has to be authored.
#
# Usage:
#   ./bin/backmerge.sh            # bring $BASE level with $HEAD
#   ./bin/backmerge.sh --dry-run  # report the decision, touch nothing
#
# Env:
#   BACKMERGE_BASE (default develop), BACKMERGE_HEAD (default main)
#
# Pushing to a protected branch needs an identity the branch ruleset lets
# through. In CI that is the deploy key; run by hand this reports the rejection
# rather than pretending, which is why --dry-run exists.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

BASE="${BACKMERGE_BASE:-develop}"
HEAD="${BACKMERGE_HEAD:-main}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

require git "install git"

git fetch origin --quiet "$BASE" "$HEAD" 2>/dev/null || true

base_sha=$(git rev-parse "origin/$BASE")
head_sha=$(git rev-parse "origin/$HEAD")

# Already level: everything on $HEAD is reachable from $BASE.
if git merge-base --is-ancestor "$head_sha" "$base_sha"; then
    log_info "$BASE already contains $HEAD — nothing to back-merge."
    exit 0
fi

count=$(git rev-list --count "origin/$BASE..origin/$HEAD")

# Whether anything on $HEAD is original work rather than release plumbing.
# Merge commits are not work: their content reached $HEAD from $BASE in the
# first place. A non-merge commit here is a hotfix landed straight on $HEAD,
# and it is the only thing that changes what a reader should look at.
original=$(git log --no-merges --format='- %s' "origin/$BASE..origin/$HEAD")

# A fast-forward is possible exactly when $BASE is an ancestor of $HEAD: $BASE
# has nothing $HEAD lacks, so advancing it discards nothing. That covers every
# routine back-merge, and a hotfix too, since a hotfix reached $HEAD through its
# own reviewed pull request and is not new content arriving unexamined.
if git merge-base --is-ancestor "$base_sha" "$head_sha"; then
    if [ -n "$original" ]; then
        log_warn "$HEAD carries $(printf '%s\n' "$original" | grep -c .) commit(s) of its own; the fast-forward brings real file changes to $BASE:"
        printf '%s\n' "$original" >&2
    else
        log_info "Routine back-merge: $count commit(s) of release plumbing, no file changes."
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "Would fast-forward $BASE to ${head_sha:0:8} (dry run, nothing pushed)."
        exit 0
    fi

    # Push the commit itself rather than a local ref: nothing here needs a
    # checkout of $BASE, and a stale local branch cannot creep into the push.
    if git push origin "$head_sha:refs/heads/$BASE"; then
        log_ok "Fast-forwarded $BASE to ${head_sha:0:8}."
        exit 0
    fi
    log_error "Fast-forward push to $BASE was rejected.
The branch ruleset requires an identity allowed to bypass its pull-request rule;
CI uses the deploy key for this. Run with --dry-run to inspect without pushing."
fi

# No fast-forward: $BASE has commits $HEAD lacks, so levelling them needs a
# merge commit somebody has to author. That is a real change to $BASE and goes
# through review like any other.
log_warn "$BASE has moved on, so this cannot be a fast-forward; opening a pull request instead."

require gh "brew install gh"

subjects=$(git log "origin/$BASE..origin/$HEAD" --format='- %s' | head -40)
if [ -n "$original" ]; then
    nature="**Carries file changes.** \`$HEAD\` holds commits of its own, so this is a hotfix coming home. Review it as a normal change."
else
    nature="**History only.** Nothing on \`$HEAD\` is original work; this merge commit exists to record that \`$BASE\` contains it."
fi

body=$(cat <<BODY
## 👥 High-level summary

Releases move code one way, from the integration branch to the release branch, and each one leaves a merge commit behind that the integration branch never receives. Normally that is repaired by fast-forwarding, which needs no pull request because nothing is being decided. This one could not be: the integration branch has moved on since the release, so bringing the two level needs a merge commit that somebody has to author, and authoring is what review is for.

## 📋 What changed

$nature

<details>
<summary>Commits being brought back ($count)</summary>

$subjects

</details>

## ✅ Test plan

- [ ] \`git diff origin/$BASE origin/$HEAD\` reviewed
- [ ] If it carries file changes: suite run on the merge result

## 🤖 Review

- [ ] Automated/AI review has run and its comments have been read

---

*Opened by \`bin/backmerge.sh\`, which opens a pull request only when a
fast-forward is impossible. If its checks show as runs with no jobs, they are
held for approval because a workflow opened this: approve them from the merge
box, because unlike a routine back-merge this one has something to test.*
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
    log_ok "Back-merge PR opened — it needs a human, unlike a fast-forward."
fi
