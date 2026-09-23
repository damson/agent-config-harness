#!/usr/bin/env bash
#
# AI Setup — does the rubric still know a bad config from a good one?
#
# A scoring rubric can be made stable by making it blind: narrow the spread
# between runs by narrowing the range it can express, and every file drifts
# toward the same comfortable number. That happened here. A rubric change
# measured only for stability looked like a success while the repository's own
# degraded example had moved from F to B.
#
# So this scores the pair the repo already ships, as a rubric changes:
#
#   workspace/backend-node/CLAUDE.md   the example config, as shipped
#   evals/examples/degraded.md         the same file plus familiar rot
#
# and fails unless the good one still scores well, the rotted one still scores
# badly, and the gap between them is wide enough to act on.
#
# Not in CI: it spends a model call per file. Run it when the rubric or the
# scoring code changes, and paste the numbers into the pull request.
#
# Usage:
#   ./bin/calibrate-rubric.sh
#
# Env:
#   EVAL_MODEL — as everywhere else; calibrate on the model you score with.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

require jq     "brew install jq"
require claude "Install Claude CLI"

GOOD_SRC="$HARNESS_ROOT/workspace/backend-node/CLAUDE.md"
ROT_SRC="$HARNESS_ROOT/evals/examples/degraded.md"
[ -f "$GOOD_SRC" ] || log_error "Missing the good example: $GOOD_SRC"
[ -f "$ROT_SRC" ]  || log_error "Missing the degraded example: $ROT_SRC"

# What the pair has to show. A rubric that cannot separate these two by this
# much cannot separate anything a reader would care about.
GOOD_MIN=${CALIBRATE_GOOD_MIN:-20}   # B or better
ROT_MAX=${CALIBRATE_ROT_MAX:-16}     # D or worse
GAP_MIN=${CALIBRATE_GAP_MIN:-6}

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/config" "$root/good" "$root/rot"
cp "$GOOD_SRC" "$root/good/CLAUDE.md"
cp "$ROT_SRC"  "$root/rot/CLAUDE.md"
printf 'good = good : CLAUDE.md\nrot = rot : CLAUDE.md\n' >"$root/config/domains.conf"

score_of() {
    local domain="$1" result
    AGENT_CONFIG_ROOT="$root" "$HARNESS_ROOT/evals/run-eval.sh" "$domain" >/dev/null 2>&1 || true
    result=$(ls -t "$root/evals/results/"*"-$domain.json" 2>/dev/null | head -1)
    [ -n "$result" ] || { printf '0'; return; }
    jq -r '.total // 0' "$result"
}

log_info "Scoring the shipped example and its degraded twin. Two model calls."
good=$(score_of good)
rot=$(score_of rot)
gap=$((good - rot))

printf '\n  good: %s/25\n  rot:  %s/25\n  gap:  %s\n\n' "$good" "$rot" "$gap"

failed=0
if [ "$good" -lt "$GOOD_MIN" ]; then
    log_warn "The shipped example scored $good/25, below the $GOOD_MIN this rubric should give it."
    failed=1
fi
if [ "$rot" -gt "$ROT_MAX" ]; then
    log_warn "The degraded example scored $rot/25. A rubric that cannot fail it cannot fail anything."
    failed=1
fi
if [ "$gap" -lt "$GAP_MIN" ]; then
    log_warn "The gap is $gap points, under the $GAP_MIN a reader needs to act on a score."
    failed=1
fi

if [ "$failed" -eq 1 ]; then
    log_error "Calibration failed. Scores move between runs, so re-run once before believing it; twice failing is the rubric, not the noise."
fi

log_ok "Calibration passed: $good vs $rot, gap $gap."
