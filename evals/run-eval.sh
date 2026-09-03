#!/usr/bin/env bash
#
# AI Setup — Eval Runner
#
# Assembles the file stack for a domain, calls the Claude CLI with the
# scoring prompt, validates the JSON response, and writes results to
# evals/results/ + benchmarks/scores/.
#
# Usage:
#   ./evals/run-eval.sh mobile        # single domain
#   ./evals/run-eval.sh all           # all registered domains
#
# Env:
#   EVAL_MODEL — model to score with (pinned default in lib/scoring.sh).
#
# Requires: claude (CLI), jq. ajv-cli optional for schema validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/scoring.sh
. "$HARNESS_ROOT/lib/scoring.sh"

require jq    "brew install jq"
require claude "Install Claude CLI"

PROMPT="$HARNESS_ROOT/evals/prompts/config-quality.md"
RESULTS_DIR="$REPO_ROOT/evals/results"
SCORES_DIR="$REPO_ROOT/benchmarks/scores"
mkdir -p "$RESULTS_DIR" "$SCORES_DIR"

[ -f "$PROMPT" ] || log_error "Prompt missing: $PROMPT"

target="${1:-all}"
domains_to_run=()
if [ "$target" = "all" ]; then
    while IFS= read -r d; do
        [ -n "$d" ] && domains_to_run+=("$d")
    done < <(list_domains)
else
    domain_exists "$target" || log_error "Unknown domain: $target"
    domains_to_run=("$target")
fi

git_hash=$(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# ── Score one domain ──────────────────────────────────────
score_domain() {
    local domain="$1"
    local ws
    ws=$(get_domain_workspace "$domain")
    log_info "Scoring domain: $domain"

    # Assemble the prompt + file stack
    local tmp_prompt
    tmp_prompt=$(mktemp)
    cat "$PROMPT" >"$tmp_prompt"
    {
        printf '\n\n### Domain context\n'
        printf 'domain: %s\n' "$domain"
        printf 'git_hash: %s\n' "$git_hash"
        printf 'date: %s\n' "$timestamp"
    } >>"$tmp_prompt"

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        local fp="$REPO_ROOT/$ws/$f"
        if [ -f "$fp" ]; then
            append_scored_file "$tmp_prompt" "$ws/$f" "$fp"
        fi
    done < <(get_domain_files "$domain")

    # The shared half of the pipeline: claude call → JSON extraction →
    # validation → result + score records → findings summary.
    score_prompt "$domain" "$domain" "$tmp_prompt" \
        '.findings[] | "    - [\(.dimension)] \(.file)/\(.section): \(.issue)"'
}

# ── Run all targets ───────────────────────────────────────
failed=0
for d in "${domains_to_run[@]}"; do
    if ! score_domain "$d"; then
        failed=$((failed + 1))
    fi
done

if [ "$failed" -gt 0 ]; then
    log_warn "$failed domain(s) failed scoring."
    exit 1
fi

log_ok "All scoring complete."
