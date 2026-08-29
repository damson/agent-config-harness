#!/usr/bin/env bash
#
# AI Setup — Secret Linter
#
# Scans tracked files for actual secret value patterns. Tries hard to avoid
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
    # Stripe live keys
    'sk_live_[A-Za-z0-9]{16,}'
    # Slack incoming webhooks
    'https://hooks\.slack\.com/services/[A-Za-z0-9/_\-]{20,}'
    # AWS-style access key ID
    '\bAKIA[0-9A-Z]{16}\b'
    # Private key headers
    '-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----'
)

EXCLUDE_DIRS=(
    --exclude-dir='.git'
    --exclude-dir='node_modules'
    --exclude-dir='evals/results'
    --exclude-dir='benchmarks/scores'
)
EXCLUDE_FILES=(
    --exclude='SYNC_LOG.md'
    --exclude='SETUP_LOG.md'
    --exclude='lint-secrets.sh'   # this file contains the patterns themselves
)

log_info "Scanning for secret value patterns..."

found=0
for pattern in "${PATTERNS[@]}"; do
    # -P would be ideal but is not portable. Use -E with caveats.
    if matches=$(grep -rIEn "$pattern" "$REPO_ROOT" "${EXCLUDE_DIRS[@]}" "${EXCLUDE_FILES[@]}" 2>/dev/null); then
        if [ -n "$matches" ]; then
            log_warn "Pattern matched: $pattern"
            printf '%s\n' "$matches" >&2
            found=$((found + 1))
        fi
    fi
done

if [ "$found" -eq 0 ]; then
    log_ok "No secret values detected."
    exit 0
else
    log_warn "Found $found suspect pattern(s). Review before pushing."
    exit 1
fi
