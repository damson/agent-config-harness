#!/usr/bin/env bash
#
# AI Setup — Skill Eval Runner
#
# Scores every SKILL.md under user-dev/skills/ using evals/prompts/skill-quality.md
# and writes results to evals/results/ + benchmarks/scores/ with domain = "skill:<name>".
#
# Usage:
#   ./evals/run-skill-eval.sh                  # all skills
#   ./evals/run-skill-eval.sh rewrite-pr-history   # one skill by name
#
# Requires: claude (CLI), jq.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

require jq    "brew install jq"
require claude "Install Claude CLI"

PROMPT="$REPO_ROOT/evals/prompts/skill-quality.md"
SCHEMA="$REPO_ROOT/evals/eval-schema.json"
RESULTS_DIR="$REPO_ROOT/evals/results"
SCORES_DIR="$REPO_ROOT/benchmarks/scores"
SKILLS_DIR="$REPO_ROOT/user-dev/skills"
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

    local tmp_prompt
    tmp_prompt=$(mktemp)
    cat "$PROMPT" >"$tmp_prompt"
    {
        printf '\n\n### Context\n'
        printf 'domain: %s\n' "$domain"
        printf 'git_hash: %s\n' "$git_hash"
        printf 'date: %s\n' "$timestamp"
        printf '\n\n### File: %s/SKILL.md\n```\n' "$rel"
        cat "$skill_file"
        printf '\n```\n'
    } >>"$tmp_prompt"

    local response
    if ! response=$(claude --print < "$tmp_prompt" 2>/dev/null); then
        log_warn "Claude CLI invocation failed for $skill"
        rm -f "$tmp_prompt"
        return 1
    fi
    rm -f "$tmp_prompt"

    # Extract the JSON object from the reply (see extract_json_object in
    # lib/common.sh — the reply may be fenced or wrapped in prose).
    local json
    json=$(printf '%s' "$response" | extract_json_object)

    if ! printf '%s' "$json" | jq empty >/dev/null 2>&1; then
        log_warn "Output for $skill was not valid JSON. Saved raw response."
        printf '%s' "$response" >"$RESULTS_DIR/${timestamp%T*}-skill-$skill-RAW.txt"
        return 1
    fi

    if command -v ajv >/dev/null 2>&1; then
        if ! printf '%s' "$json" | ajv validate -s "$SCHEMA" --strict=false >/dev/null 2>&1; then
            log_warn "Output for $skill failed schema validation."
        fi
    fi

    # Domain is the same string used on disk so benchmarks/report.sh can pattern-match.
    local out_path score_path
    out_path="$RESULTS_DIR/${timestamp%T*}-$domain.json"
    score_path="$SCORES_DIR/${timestamp%T*}-$domain.json"
    printf '%s\n' "$json" >"$out_path"

    jq '{date, domain, git_hash, scores, total, percentage, grade}' \
        <"$out_path" >"$score_path"

    log_ok "Result written: $out_path"
    log_info "  Total: $(jq -r .total <"$out_path")/25  Grade: $(jq -r .grade <"$out_path")"

    local n_findings
    n_findings=$(jq '.findings | length' <"$out_path")
    if [ "$n_findings" -gt 0 ]; then
        log_info "  Findings ($n_findings):"
        jq -r '.findings[] | "    - [\(.dimension)] \(.section): \(.issue)"' <"$out_path"
    fi
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
