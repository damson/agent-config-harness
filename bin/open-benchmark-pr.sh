#!/usr/bin/env bash
#
# AI Setup — publish benchmark score snapshots as a standing pull request.
#
# `just benchmark` prints a trend, and for months it had no trend to print: one
# row per domain, from whichever afternoon somebody last ran `just eval` by
# hand. Scores are gitignored and committed deliberately (`just benchmark-commit`),
# so an automated run that scored the domains and stopped there left nothing
# behind.
#
# This takes the scores a run just wrote, commits them onto a standing branch,
# and opens or refreshes one pull request that carries the accumulated trend.
# It never merges: promoting a measurement into the repository's history stays a
# human decision, the same way the release PR does.
#
# One pull request, refreshed, rather than one per run. A weekly PR full of JSON
# is noise that teaches everyone to close it unread.
#
# Usage:
#   ./bin/open-benchmark-pr.sh            # commit, push, open or refresh
#   ./bin/open-benchmark-pr.sh --dry-run  # print the body, touch nothing
#
# Env:
#   BENCHMARK_BRANCH (default benchmark/scores)
#   BENCHMARK_BASE   (default develop)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

BRANCH="${BENCHMARK_BRANCH:-benchmark/scores}"
BASE="${BENCHMARK_BASE:-develop}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

require git "install git"
require jq  "brew install jq"
[ "$DRY_RUN" -eq 1 ] || require gh "brew install gh"

SCORES_DIR="$REPO_ROOT/benchmarks/scores"

# Score records only. A run that failed every domain leaves the directory as it
# found it, and publishing nothing is the honest outcome: an empty pull request
# reads as "measured, all fine".
new_scores=()
for f in "$SCORES_DIR"/*.json; do
    [ -f "$f" ] || continue
    new_scores+=("$f")
done

if [ "${#new_scores[@]}" -eq 0 ]; then
    log_info "No score records in $SCORES_DIR — nothing to publish."
    exit 0
fi

# body <scores_root>
#
# The trend table as the branch will render it, so the pull request shows the
# accumulated history rather than the single run that refreshed it. Reading it
# from a root keeps that honest: the caller passes the temp worktree after the
# commit, and --dry-run passes this checkout.
body() {
    local root="$1" trend
    trend=$(AGENT_CONFIG_ROOT="$root" "$HARNESS_ROOT/benchmarks/report.sh")

    cat <<BODY
## 👥 High-level summary

Config quality is scored by an LLM on a five-dimension rubric, and the score
only means something as a series: one number says nothing about whether the
files are getting better. This pull request carries the measurements taken
since it was last merged.

Nothing here changes how the harness behaves. Merging it keeps the history;
closing it throws the measurements away.

## 📋 What changed

Score records only, under \`benchmarks/scores/\`. They are gitignored by
default and force-added here on purpose: the directory is a local artifact
until somebody decides a measurement is worth keeping.

Assembled by \`bin/open-benchmark-pr.sh\`. Every line below is regenerated on
each refresh, so edits to this section will not survive one.

\`\`\`
$trend
\`\`\`

## ✅ Test plan

- [x] The records are machine-written output of \`evals/run-eval.sh\`, validated
      against \`evals/eval-schema.json\` before they were written.
- [ ] Scores move by 1 to 2 points between runs on borderline cases. Read a
      single row as a measurement, never as a trend.
BODY
}

if [ "$DRY_RUN" -eq 1 ]; then
    body "$REPO_ROOT"
    exit 0
fi

git fetch origin --quiet "$BASE" 2>/dev/null || true
git fetch origin --quiet "$BRANCH" 2>/dev/null || true

# Always build from the base, never from the branch's own last state.
#
# The branch used to grow from itself, and the base merges its content by
# squash, so nothing on the branch ever became an ancestor of the base. Every
# record it had ever carried stayed in the diff: the second pull request listed
# twelve files, six of which were already on the integration branch with
# identical content, and that set grows by one run per cycle.
#
# Rebuilt from the base each time, the branch means exactly one thing: the
# records the base does not have yet.
#
# A detached worktree, not a checkout of the branch: the branch may already be
# checked out somewhere (a person's own worktree), and `git worktree add` of a
# branch that is refuses outright. Pushing HEAD to the ref by name needs no
# local branch at all.
tmp=$(mktemp -d)
rm -rf "$tmp"
git worktree add --detach --quiet "$tmp" "origin/$BASE"
# shellcheck disable=SC2064
trap "git worktree remove --force '$tmp' >/dev/null 2>&1 || true" EXIT

mkdir -p "$tmp/benchmarks/scores"

# Carry forward what the open pull request is still holding. Those records are
# on the branch and not in the base, and rebuilding from the base alone would
# drop them: a CI checkout has only the run that just happened.
if git rev-parse --verify --quiet "origin/$BRANCH" >/dev/null; then
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        git show "origin/$BRANCH:$path" >"$tmp/$path" 2>/dev/null || true
    done < <(git diff --name-only --diff-filter=AM "origin/$BASE" "origin/$BRANCH" -- benchmarks/scores)
fi

cp "${new_scores[@]}" "$tmp/benchmarks/scores/"

# -f because benchmarks/scores/* is gitignored. Without it `git add` reports
# success, stages nothing, and the run ends having published an empty commit or
# no commit at all while saying it published scores.
git -C "$tmp" add -f benchmarks/scores

if git -C "$tmp" diff --cached --quiet; then
    log_info "Every score record is already on $BASE — nothing new to publish."
    exit 0
fi

# Rebuilding from the base produces a fresh commit every run, so "has anything
# changed" has to be asked of the tree rather than of the commit. Without this
# the pull request collects one empty-diff commit per run, which is the noise
# that teaches a reviewer to stop opening it.
if git rev-parse --verify --quiet "origin/$BRANCH" >/dev/null; then
    if [ "$(git -C "$tmp" write-tree)" = "$(git rev-parse "origin/$BRANCH^{tree}")" ]; then
        log_info "$BRANCH already carries exactly these records — nothing new to publish."
        exit 0
    fi
fi

count=$(git -C "$tmp" diff --cached --name-only | wc -l | tr -d ' ')

# -c rather than `git config`: this must not write identity into anybody's
# repository, and a CI runner has none to borrow.
git -C "$tmp" \
    -c user.name="${BENCHMARK_GIT_NAME:-github-actions[bot]}" \
    -c user.email="${BENCHMARK_GIT_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}" \
    commit --quiet -m "benchmark: $count score snapshot(s)"

# Force, because the branch is rebuilt from the base rather than extended, and
# it is owned by this script alone. Nobody commits to it by hand.
git -C "$tmp" push --quiet --force origin "HEAD:refs/heads/$BRANCH"
log_ok "Pushed $count score record(s) to $BRANCH"

pr_body=$(body "$tmp")

# One line, deliberately. kcov reports the first line of a multi-line command
# substitution as never executed: 9 of the 9 in this repository read that way
# and none reads as hit, so wrapping this for width would cost a line of
# coverage that no test can win back. Not a case for the ignore markers, which
# are for data and foreign source; a bash statement inside a region stops being
# measured at all.
existing=$(gh pr list --base "$BASE" --head "$BRANCH" --state open --json number --jq '.[0].number // empty')

if [ -n "$existing" ]; then
    log_info "Refreshing benchmark PR #$existing"
    gh pr edit "$existing" --body "$pr_body"
    log_ok "Updated #$existing"
else
    log_info "Opening the benchmark PR"
    gh pr create --base "$BASE" --head "$BRANCH" \
        --title "benchmark: config quality score snapshots" \
        --body "$pr_body"
    log_ok "Benchmark PR opened — merging it is a human decision."
fi
