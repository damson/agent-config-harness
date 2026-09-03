#!/usr/bin/env bash
#
# AI Setup — post (or refresh) a PR's code-coverage comment.
#
# Reads the coverage.json a kcov run leaves in its merged output directory and
# upserts ONE comment on the pull request — found again by the marker on its
# first line and edited in place, because a fresh comment per push buries the
# conversation under a bot monologue.
#
# It never gates. Coverage of a bash codebase measured through its test suite
# is a flashlight, not a tripwire: kcov cannot see lines that only run on
# another OS or against a real API, so a threshold here would punish honesty.
#
# Usage:
#   ./bin/post-coverage-comment.sh <pr-number> <kcov-merged-dir>
#   ./bin/post-coverage-comment.sh <pr-number> <kcov-merged-dir> --dry-run
#
# Env:
#   GITHUB_REPOSITORY   owner/repo (set by Actions; asked from gh otherwise)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/common.sh"

require jq
require gh "install the GitHub CLI"

MARKER='<!-- coverage-report -->'

pr="${1:-}"; dir="${2:-}"; dry="${3:-}"
case "$pr" in ''|*[!0-9]*) log_error "Usage: $0 <pr-number> <kcov-merged-dir> [--dry-run]";; esac
json="$dir/coverage.json"
[ -f "$json" ] || log_error "No coverage.json in '$dir' — did the kcov run produce output?"

repo="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

# kcov reports absolute paths; the comment wants repo-relative ones. Worst
# covered first, so the actionable rows are the ones a reader sees without
# scrolling.
body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT
{
    printf '%s\n' "$MARKER"
    jq -r '"## 🧪 Coverage: \(.percent_covered)% (\(.covered_lines)/\(.total_lines) lines)"' "$json"
    printf '\n'
    printf '| File | Coverage | Lines |\n|---|---|---|\n'
    jq -r --arg root "$REPO_ROOT/" '
        .files
        | map(.percent_covered |= tonumber)
        | sort_by(.percent_covered)[]
        | "| `\(.file | sub("^" + $root; ""))` | \(.percent_covered)% | \(.covered_lines)/\(.total_lines) |"
    ' "$json"
    printf '\n*Measured by kcov over the bats suite. Informational — no threshold.*\n'
} > "$body_file"

if [ "$dry" = "--dry-run" ]; then
    cat "$body_file"
    exit 0
fi

existing=$(gh api "repos/$repo/issues/$pr/comments" --paginate \
    --jq "[.[] | select(.body | startswith(\"$MARKER\"))][0].id // empty")

if [ -n "$existing" ]; then
    gh api -X PATCH "repos/$repo/issues/comments/$existing" -F body=@"$body_file" >/dev/null
    log_ok "Refreshed coverage comment on PR #$pr"
else
    gh api -X POST "repos/$repo/issues/$pr/comments" -F body=@"$body_file" >/dev/null
    log_ok "Posted coverage comment on PR #$pr"
fi
