#!/usr/bin/env bash
#
# AI Setup — Eval Runner
#
# Assembles the file stack for a domain, calls the Claude CLI with the
# scoring prompt, validates the JSON response, and writes results to
# evals/results/ + benchmarks/scores/.
#
# Usage:
#   ./evals/run-eval.sh android       # single domain
#   ./evals/run-eval.sh all           # all registered domains
#
# Requires: claude (CLI), jq. ajv-cli optional for schema validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

require jq    "brew install jq"
require claude "Install Claude CLI"

PROMPT="$HARNESS_ROOT/evals/prompts/config-quality.md"
SCHEMA="$HARNESS_ROOT/evals/eval-schema.json"
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
            {
                printf '\n\n### File: %s/%s\n```\n' "$ws" "$f"
                cat "$fp"
                printf '\n```\n'
            } >>"$tmp_prompt"
        fi
    done < <(get_domain_files "$domain")

    # Call Claude CLI; expect raw JSON in the response.
    local response
    if ! response=$(claude --print < "$tmp_prompt" 2>/dev/null); then
        log_warn "Claude CLI invocation failed for $domain"
        rm -f "$tmp_prompt"
        return 1
    fi
    rm -f "$tmp_prompt"

    # Extract the JSON object from the reply (see extract_json_object in
    # lib/common.sh — the reply may be fenced or wrapped in prose).
    local json
    json=$(printf '%s' "$response" | extract_json_object)

    # Validate JSON parses
    if ! printf '%s' "$json" | jq empty >/dev/null 2>&1; then
        log_warn "Output for $domain was not valid JSON. Saved raw response."
        printf '%s' "$response" >"$RESULTS_DIR/${timestamp%T*}-$domain-RAW.txt"
        return 1
    fi

    # Validate against schema if ajv is available
    if command -v ajv >/dev/null 2>&1; then
        if ! printf '%s' "$json" | ajv validate -s "$SCHEMA" --strict=false >/dev/null 2>&1; then
            log_warn "Output for $domain failed schema validation."
        fi
    fi

    local out_path score_path
    out_path="$RESULTS_DIR/${timestamp%T*}-$domain.json"
    score_path="$SCORES_DIR/${timestamp%T*}-$domain.json"
    printf '%s\n' "$json" >"$out_path"

    # Write a compact score record for benchmark trending.
    jq '{date, domain, git_hash, scores, total, percentage, grade}' \
        <"$out_path" >"$score_path"

    log_ok "Result written: $out_path"
    log_info "  Total: $(jq -r .total <"$out_path")/25  Grade: $(jq -r .grade <"$out_path")"

    # Print findings summary
    local n_findings
    n_findings=$(jq '.findings | length' <"$out_path")
    if [ "$n_findings" -gt 0 ]; then
        log_info "  Findings ($n_findings):"
        jq -r '.findings[] | "    - [\(.dimension)] \(.file)/\(.section): \(.issue)"' <"$out_path"
    fi
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
