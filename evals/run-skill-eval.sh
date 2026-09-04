#!/usr/bin/env bash
#
# AI Setup — Skill Eval Runner
#
# Scores every SKILL.md under the managed repo's user-dev/skills/ (or SKILLS_DIR)
# using the harness's evals/prompts/skill-quality.md
# and writes results to evals/results/ + benchmarks/scores/ with domain = "skill-<name>".
#
# Usage:
#   ./evals/run-skill-eval.sh                  # all skills
#   ./evals/run-skill-eval.sh rewrite-pr-history   # one skill by name
#
# Env:
#   EVAL_MODEL — model to score with (pinned default in lib/scoring.sh).
#
# Requires: claude (CLI), jq.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/scoring.sh
. "$HARNESS_ROOT/lib/scoring.sh"

require jq    "brew install jq"
require claude "Install Claude CLI"

PROMPT="$HARNESS_ROOT/evals/prompts/skill-quality.md"
RESULTS_DIR="$REPO_ROOT/evals/results"
SCORES_DIR="$REPO_ROOT/benchmarks/scores"
# Default to this repo's skills; SKILLS_DIR points it at any tree, which is how
# `just eval-skills --marketplace <id>` scores skills this repo does not own.
SKILLS_DIR="${SKILLS_DIR:-$REPO_ROOT/user-dev/skills}"
mkdir -p "$RESULTS_DIR" "$SCORES_DIR"

[ -f "$PROMPT" ] || log_error "Prompt missing: $PROMPT"
[ -d "$SKILLS_DIR" ] || log_error "Skills directory missing: $SKILLS_DIR"

# Skills are addressed by leaf name but may live one level down in a group
# container, so resolve names to paths through the shared discovery helper.
target="${1:-all}"
skills_to_run=()
if [ "$target" = "all" ]; then
    while IFS= read -r d; do
        skills_to_run+=("$d")
    done < <(list_skill_dirs | sort)
else
    while IFS= read -r d; do
        [ "$(basename "$d")" = "$target" ] && skills_to_run=("$d")
    done < <(list_skill_dirs)
    [ "${#skills_to_run[@]}" -gt 0 ] || log_error "Unknown skill: $target"
fi

git_hash=$(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# ── Score one skill ──────────────────────────────────────
score_skill() {
    local skill_dir="$1"
    local skill skill_file rel
    skill="$(basename "$skill_dir")"
    skill_file="$skill_dir/SKILL.md"
    rel="${skill_dir#"$REPO_ROOT"/}"
    local domain="skill-$skill"
    log_info "Scoring skill: $skill"

    local tmp_prompt nonce
    tmp_prompt=$(mktemp)
    nonce=$(scored_nonce)
    cat "$PROMPT" >"$tmp_prompt"
    scored_content_preamble "$nonce" >>"$tmp_prompt"
    {
        printf '\n\n### Context\n'
        printf 'domain: %s\n' "$domain"
        printf 'git_hash: %s\n' "$git_hash"
        printf 'date: %s\n' "$timestamp"
    } >>"$tmp_prompt"
    append_scored_file "$tmp_prompt" "$rel/SKILL.md" "$skill_file" "$nonce"

    # The shared half of the pipeline: claude call → JSON extraction →
    # validation → result + score records → findings summary. The domain string
    # is the filename identity, so records land beside the domain evals'.
    score_prompt "$skill" "$domain" "$tmp_prompt" \
        '.findings[] | "    - [\(.dimension)] \(.section): \(.issue)"'
}

failed=0
for s in "${skills_to_run[@]}"; do
    if ! score_skill "$s"; then
        failed=$((failed + 1))
    fi
done

if [ "$failed" -gt 0 ]; then
    log_warn "$failed skill(s) failed scoring."
    exit 1
fi

log_ok "All skill scoring complete."
