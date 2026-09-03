#!/usr/bin/env bash
#
# AI Setup — Secret Linter
#
# Scans tracked files (git ls-files — untracked local state like .remember/
# or logs is noise) for actual secret value patterns. Tries hard to avoid
# false positives in documentation (e.g. the word "secret" appearing in
# prose). For each pattern, we require a value-like context (assignment,
# explicit token shape) rather than the word alone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

# Patterns: each entry is a regex that matches a credential VALUE, not just
# a word. Adjust here to add more.
PATTERNS=(
    # API keys assigned to a value (`API_KEY=foo`, `apiKey: "foo"`).
    '(api[_-]?key)["'\'']?\s*[:=]\s*["'\'']?[A-Za-z0-9_\-]{8,}'
    # secret/password/token assigned to a value
    '(secret|password|passwd|token)["'\'']?\s*[:=]\s*["'\'']?[A-Za-z0-9_\-]{8,}'
    # Bearer tokens with an actual token after them
    'Bearer[[:space:]]+[A-Za-z0-9._\-]{16,}'
    # GitHub personal access tokens
    'ghp_[A-Za-z0-9]{20,}'
    # Anthropic API keys
    'sk-ant-[A-Za-z0-9_\-]{16,}'
    # Stripe live keys
    'sk_live_[A-Za-z0-9]{16,}'
    # Slack incoming webhooks
    'https://hooks\.slack\.com/services/[A-Za-z0-9/_\-]{20,}'
    # AWS-style access key ID
    '\bAKIA[0-9A-Z]{16}\b'
    # Private key headers
    '-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----'
)

# Git pathspecs, not grep --exclude-dir: --exclude-dir takes a bare directory
# NAME, so a path like 'evals/results' never matched anything. Pathspecs
# handle full paths, and git ls-files limits the scan to tracked files.
EXCLUDE_PATHSPECS=(
    ':(exclude)evals/results'
    ':(exclude)benchmarks/scores'
    ':(exclude,glob)**/SYNC_LOG.md'
    ':(exclude,glob)**/SETUP_LOG.md'
    ':(exclude)bin/lint-secrets.sh'      # contains the patterns themselves
    ':(exclude)tests/lint-secrets.bats'  # contains fixtures that must match them
)

cd "$REPO_ROOT"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    log_error "Not a git repository: $REPO_ROOT (the linter scans tracked files)"

log_info "Scanning tracked files for secret value patterns..."

found=0
for pattern in "${PATTERNS[@]}"; do
    # -P would be ideal but is not portable. Use -E with caveats.
    # -e keeps a pattern starting with '-' from being read as options.
    matches=$(git ls-files -z -- "${EXCLUDE_PATHSPECS[@]}" \
        | xargs -0 grep -IHEn -e "$pattern" 2>/dev/null) || true
    if [ -n "$matches" ]; then
        log_warn "Pattern matched: $pattern"
        printf '%s\n' "$matches" >&2
        found=$((found + 1))
    fi
done

if [ "$found" -eq 0 ]; then
    log_ok "No secret values detected."
    exit 0
else
    log_warn "Found $found suspect pattern(s). Review before pushing."
    exit 1
fi
