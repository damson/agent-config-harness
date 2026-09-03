# shellcheck shell=bash
#
# AI Setup — Shared Scoring Library
#
# Sourced by evals/run-eval.sh and evals/run-skill-eval.sh AFTER lib/common.sh.
# Owns the half of the pipeline the two runners share: calling the Claude CLI
# on an assembled prompt, extracting and validating the JSON reply, writing the
# result + score records, and printing the findings summary.
#
# Callers provide (as globals, matching the runners' existing style):
#   RESULTS_DIR  where full result JSON (and RAW fallbacks) land
#   SCORES_DIR   where compact score records land
#   timestamp    the run's UTC ISO 8601 timestamp (one per run)
#
# Env:
#   EVAL_MODEL   model the eval runs on. Pinned by default so scores stay
#                comparable across machines and over time; override to compare
#                models deliberately, not accidentally.

EVAL_MODEL="${EVAL_MODEL:-claude-sonnet-5}"

# The schema is a harness asset (HARNESS_ROOT, never REPO_ROOT), used for the
# optional ajv validation in score_prompt.
SCHEMA="$HARNESS_ROOT/evals/eval-schema.json"

# append_scored_file <prompt_file> <display_path> <file_path>
#
# Append one file under evaluation to the assembled prompt, wrapped in explicit
# BEGIN/END markers. The scoring prompts instruct the evaluator that everything
# between the markers is data to be scored, never instructions — a prompt-
# injection mitigation (bypass-resistant, not bypass-proof).
append_scored_file() {
    local prompt_file="$1" display="$2" file_path="$3"
    {
        printf '\n\n### File: %s\n' "$display"
        printf '<<<BEGIN SCORED CONTENT: %s>>>\n```\n' "$display"
        cat "$file_path"
        printf '\n```\n<<<END SCORED CONTENT: %s>>>\n' "$display"
    } >>"$prompt_file"
}

# score_prompt <label> <domain> <prompt_file> <findings_filter>
#
#   label            name used in log messages (a domain, or a skill's short name)
#   domain           identity written into filenames ("mobile", "skill-<name>")
#   prompt_file      assembled prompt; consumed and removed
#   findings_filter  jq filter rendering one finding per line
#
# Returns non-zero when the CLI call fails or the reply holds no parsable JSON
# object (raw reply saved as <stamp>-<domain>-RAW.txt in that case).
score_prompt() {
    local label="$1" domain="$2" prompt_file="$3" findings_filter="$4"

    # Filename stem: the run timestamp down to the second, minus the characters
    # filenames dislike (2026-09-02T18:30:00Z → 2026-09-02T183000). Seconds
    # precision keeps a same-day rerun from overwriting the earlier result; the
    # -<domain>.json suffix stays, so `*-<domain>.json` globs keep matching.
    local stamp="${timestamp:?score_prompt: run timestamp unset}"
    stamp="${stamp//:/}"
    stamp="${stamp%Z}"

    # Call Claude CLI; expect raw JSON in the response. Keep stderr — it is the
    # only diagnostic when the call fails (bad API key, network, rate limit).
    local response stderr_file
    stderr_file=$(mktemp)
    if ! response=$(claude --print --model "$EVAL_MODEL" <"$prompt_file" 2>"$stderr_file"); then
        log_warn "Claude CLI invocation failed for $label"
        if [ -s "$stderr_file" ]; then
            log_warn "  claude stderr: $(cat "$stderr_file")"
        fi
        rm -f "$prompt_file" "$stderr_file"
        return 1
    fi
    rm -f "$prompt_file" "$stderr_file"

    # Extract the JSON object from the reply (see extract_json_object in
    # lib/common.sh — the reply may be fenced or wrapped in prose).
    local json
    json=$(printf '%s' "$response" | extract_json_object)

    # Validate JSON parses. The empty string must fail too: a reply holding no
    # object at all extracts to nothing, and `jq empty` on empty input is a
    # vacuous pass that would write an empty result and report success.
    if [ -z "$json" ] || ! printf '%s' "$json" | jq empty >/dev/null 2>&1; then
        log_warn "Output for $label was not valid JSON. Saved raw response."
        printf '%s' "$response" >"$RESULTS_DIR/$stamp-$domain-RAW.txt"
        return 1
    fi

    # Validate against schema if ajv is available
    if command -v ajv >/dev/null 2>&1; then
        if ! printf '%s' "$json" | ajv validate -s "$SCHEMA" --strict=false >/dev/null 2>&1; then
            log_warn "Output for $label failed schema validation."
        fi
    fi

    local out_path score_path
    out_path="$RESULTS_DIR/$stamp-$domain.json"
    score_path="$SCORES_DIR/$stamp-$domain.json"
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
        jq -r "$findings_filter" <"$out_path"
    fi
}
