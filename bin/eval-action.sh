#!/usr/bin/env bash
#
# Entry point for the "score your config in CI" GitHub Action (action.yml at
# the repo root). Scores config files in the CALLING repo, not this one, and
# fails the job when the grade slips below a threshold.
#
# Two modes, chosen by whether the caller has a registry:
#   EVAL_DOMAIN set   → the calling repo is a harness consumer with its own
#                       config/domains.conf; score that domain in place.
#   EVAL_DOMAIN empty → any repo at all. A throwaway AGENT_CONFIG_ROOT is
#                       synthesized: a one-line registry whose workspace is a
#                       symlink back to the calling repo, so the repo itself is
#                       never written to and needs no harness files.
#
# Env:
#   EVAL_FILES   comma-separated files to score (default: CLAUDE.md); ignored
#                when EVAL_DOMAIN is set
#   EVAL_DOMAIN  a domain registered in the calling repo's own registry
#   FAIL_BELOW   minimum passing grade A|B|C|D|F (default: C). The job fails
#                only when the grade is BELOW this.
#   TARGET_DIR   the repo being scored (default: current directory)
#
# Requires: claude (CLI, authenticated via ANTHROPIC_API_KEY), jq.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$(dirname "$SCRIPT_DIR")"

TARGET_DIR="${TARGET_DIR:-$PWD}"
EVAL_FILES="${EVAL_FILES:-CLAUDE.md}"
EVAL_DOMAIN="${EVAL_DOMAIN:-}"
FAIL_BELOW="${FAIL_BELOW:-C}"

grade_rank() {
    case "$1" in
        A) echo 5 ;; B) echo 4 ;; C) echo 3 ;; D) echo 2 ;; F) echo 1 ;;
        *) echo "Unknown grade: $1" >&2; return 1 ;;
    esac
}
threshold_rank=$(grade_rank "$FAIL_BELOW")

if [ -n "$EVAL_DOMAIN" ]; then
    root="$TARGET_DIR"
    domain="$EVAL_DOMAIN"
else
    # Synthesize a root: registry in a temp dir, workspace symlinked back to
    # the target so nothing is written into the repo being scored.
    root=$(mktemp -d)
    mkdir -p "$root/config"
    files_list=$(printf '%s' "$EVAL_FILES" | sed 's/,/, /g')
    printf 'target = ws : %s\n' "$files_list" > "$root/config/domains.conf"
    ln -s "$TARGET_DIR" "$root/ws"
    domain="target"

    IFS=',' read -ra files <<< "$EVAL_FILES"
    for f in "${files[@]}"; do
        f="${f# }"
        [ -f "$TARGET_DIR/$f" ] || { echo "::error::No such file to score: $f"; exit 1; }
    done
fi

AGENT_CONFIG_ROOT="$root" "$HARNESS/evals/run-eval.sh" "$domain"

result=$(ls -t "$root/evals/results/"*"-$domain.json" 2>/dev/null | head -1)
[ -n "$result" ] || { echo "::error::Eval produced no result file"; exit 1; }

grade=$(jq -r .grade "$result")
total=$(jq -r .total "$result")

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    { printf 'grade=%s\n' "$grade"; printf 'total=%s\n' "$total"; } >> "$GITHUB_OUTPUT"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        printf '## Config eval: %s/25 — grade %s\n\n' "$total" "$grade"
        jq -r '.findings[] | "- **\(.dimension)** \(.file)/\(.section): \(.issue)"' "$result"
    } >> "$GITHUB_STEP_SUMMARY"
fi

echo "Scored $total/25, grade $grade (threshold: below $FAIL_BELOW fails)"
if [ "$(grade_rank "$grade")" -lt "$threshold_rank" ]; then
    echo "::error::Config quality is $grade — below the $FAIL_BELOW threshold."
    exit 1
fi
