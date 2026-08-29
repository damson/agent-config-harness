#!/usr/bin/env bash
#
# AI Setup — PostToolUse Hook Handler
#
# Invoked by Claude Code after Edit/Write tool calls. Receives the full tool
# input as JSON on stdin. If the edited file is a managed config file in this
# repo, runs `just check && just lint` and prints a follow-up suggestion to
# Claude's context. Silent (no output, exit 0) for unrelated edits so it
# never interrupts normal work.
#
# Required: jq (`brew install jq`).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

# ── Read the file_path from stdin JSON ────────────────────
# Claude Code passes the tool input as JSON; the field is .tool_input.file_path
# for Edit and Write tools.
input=$(cat || true)
[ -n "$input" ] || exit 0

if ! command -v jq >/dev/null 2>&1; then
    # jq missing — silent exit; don't break the user's flow.
    exit 0
fi

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -n "$file_path" ] || exit 0

# ── Is this a managed config file in this repo? ───────────
case "$file_path" in
    "$REPO_ROOT"/*) ;;          # in this repo — continue
    *) exit 0 ;;                 # somewhere else — silent
esac

basename=$(basename "$file_path")
managed=0
case "$basename" in
    CLAUDE.md|AGENTS.md|preferences.md|user_tone_of_voice.md|custom_instructions.md|.cursorrules|domains.conf)
        managed=1 ;;
esac

# Also treat anything under config/, workspace/, user-dev/, user-pers/ as managed
case "$file_path" in
    "$REPO_ROOT"/config/*|"$REPO_ROOT"/workspace/*|"$REPO_ROOT"/user-dev/*|"$REPO_ROOT"/user-pers/*)
        managed=1 ;;
esac

[ "$managed" -eq 1 ] || exit 0

# ── Validate ──────────────────────────────────────────────
# Run check + lint. Any failure → print the failure and exit non-zero so
# Claude sees it and addresses it.
output=""
status=0

if ! check_out=$(cd "$REPO_ROOT" && "$HARNESS_ROOT/bin/check-health.sh" 2>&1); then
    output="${output}❌ Health check failed:\n${check_out}\n\n"
    status=1
fi

if ! lint_out=$(cd "$REPO_ROOT" && "$HARNESS_ROOT/bin/lint-secrets.sh" 2>&1); then
    output="${output}❌ Secret lint failed:\n${lint_out}\n\n"
    status=1
fi

if [ "$status" -ne 0 ]; then
    printf '%b' "$output"
    exit 1
fi

# ── Success: print suggestion to Claude's context ─────────
cat <<'EOF'
✅ ai-setup validation passed (check + lint).

Suggested follow-up (run in order):
  1. /agent-config-audit      — audit this change for contradictions, bloat, boundary violations
  2. /claude-md-improver      — check the edited file for clarity/conciseness wins
  3. just eval <domain>       — score the full domain stack
EOF
