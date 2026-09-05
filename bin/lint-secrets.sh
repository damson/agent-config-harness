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
#
# Assignment-style patterns match the key NAME, which is case-arbitrary in the
# wild (`API_KEY=` leaks as often as `api_key=`), so these scan with grep -i.
PATTERNS_NOCASE=(
    # API keys assigned to a value (`API_KEY=foo`, `apiKey: "foo"`).
    # [[:space:]] over \s: BSD grep is not guaranteed to expand \s in -E.
    '(api[_-]?key)["'\'']?[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9_\-]{8,}'
    # secret/password/token assigned to a value
    '(secret|password|passwd|token)["'\'']?[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9_\-]{8,}'
)

# Token-shape patterns match the secret value itself, whose case is part of
# the shape (ghp_, AKIA, sk-ant-…) — these stay case-sensitive so lookalike
# text in the wrong case does not fire.
PATTERNS=(
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

# Known-fake example values, exempted per VALUE after matching (see
# check_pattern) — never per line. Documentation and
# test stubs legitimately show what a flagged line looks like (e.g.
# docs/architecture.md's `API_KEY=abc123def`), and the invariant is "fix the
# pattern, not the doc". An allowlist of the specific fakes is preferred over
# raising the length/entropy floor: it keeps the 8-char minimum intact for
# real values and names each exemption where it can be reviewed.
ALLOWLIST_VALUES='(abc123def|stub-key)'

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

# scrub_allowlisted <content> — remove standalone allowlisted fake values from
# one line of matched content.
#
# Substitutes one occurrence per pass and repeats until the text stops
# changing, rather than using sed's /g. The boundary characters are part of
# the match, and /g resumes scanning after what it consumed, so two fakes
# separated by exactly one character left the second with no boundary left to
# match against and it survived. Each pass strictly shortens the string, so
# the loop terminates.
scrub_allowlisted() {
    local s="$1" prev
    while :; do
        prev="$s"
        s=$(printf '%s' "$s" | sed -E \
            "s/(^|[^A-Za-z0-9_-])${ALLOWLIST_VALUES}([^A-Za-z0-9_-]|\$)/\1\3/")
        # Not `[ ... ] && break`: as the last command in the loop body, a false
        # test would return non-zero and kill the script under set -e.
        if [ "$s" = "$prev" ]; then
            break
        fi
    done
    printf '%s' "$s"
}

# check_pattern <grep matcher flags> <pattern> — scan tracked files, drop
# allowlisted fake values, report anything left and bump $found.
check_pattern() {
    local flags="$1" pattern="$2" raw rec content scrubbed matches nocase=0
    # The scrub has to be as case-blind as the scan that produced the match:
    # the assignment patterns run under grep -Ei, so API_KEY=ABC123DEF matched
    # while a case-sensitive scrub left the allowlisted value untouched.
    case "$flags" in
        *i*) nocase=1 ;;
    esac
    # -P would be ideal but is not portable. Use -E with caveats.
    # -e keeps a pattern starting with '-' from being read as options.
    raw=$(git ls-files -z -- "${EXCLUDE_PATHSPECS[@]}" \
        | xargs -0 grep -IHn "$flags" -e "$pattern" 2>/dev/null) || true
    # The allowlist exempts whole fake VALUES, not lines: scrub each
    # standalone fake from the matched content and keep the record if the
    # pattern still matches what is left. A real credential sharing a line
    # with a fake still fires, and a value that merely CONTAINS a fake is
    # not exempted (the boundary classes block a mid-value scrub).
    matches=""
    while IFS= read -r rec; do
        [ -n "$rec" ] || continue
        content="${rec#*:*:}"
        # Case-fold the copy that the scrub and the re-check both look at,
        # rather than asking sed for a case-insensitive substitution: sed's
        # `I` flag is a GNU and modern-BSD extension, and where it is missing
        # sed exits non-zero and takes the whole linter down under set -e.
        # Folding is exact here because this branch re-checks with grep -i,
        # which cannot tell the two spellings apart anyway, and because the
        # record printed on a hit is the untouched original.
        # LC_ALL=C with explicit ASCII ranges: tr is byte-oriented there, so a
        # UTF-8 line passes through untouched instead of being folded by a
        # multibyte-unaware tr. The patterns are ASCII, so nothing else needs
        # folding.
        if [ "$nocase" = 1 ]; then
            content=$(printf '%s' "$content" | LC_ALL=C tr 'A-Z' 'a-z')
        fi
        scrubbed=$(scrub_allowlisted "$content")
        if printf '%s\n' "$scrubbed" | grep -q "$flags" -e "$pattern"; then
            matches+="$rec"$'\n'
        fi
    done <<< "$raw"
    matches="${matches%$'\n'}"
    if [ -n "$matches" ]; then
        log_warn "Pattern matched: $pattern"
        printf '%s\n' "$matches" >&2
        found=$((found + 1))
    fi
}

for pattern in "${PATTERNS_NOCASE[@]}"; do
    check_pattern -Ei "$pattern"
done
for pattern in "${PATTERNS[@]}"; do
    check_pattern -E "$pattern"
done

if [ "$found" -eq 0 ]; then
    log_ok "No secret values detected."
    exit 0
else
    log_warn "Found $found suspect pattern(s). Review before pushing."
    exit 1
fi
