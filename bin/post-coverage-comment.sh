#!/usr/bin/env bash
#
# AI Setup — post (or refresh) a PR's code-coverage comment.
#
# Reads the coverage.json a kcov run leaves in its merged output directory and
# upserts ONE comment on the pull request — found again by the marker on its
# first line and edited in place, because a fresh comment per push buries the
# conversation under a bot monologue.
#
# The comment carries a verdict, not just a number: a delta against the base
# branch's stored baseline when one exists, a bar that doubles as a diff
# (blue = already covered, green = added here, red = lost here), and a band
# line against the advisory floor/target. A missing baseline is not an error —
# first runs degrade to absolute figures and say so.
#
# It never gates. Coverage of a bash codebase measured through its test suite
# is a flashlight, not a tripwire: kcov cannot see lines that only run on
# another OS or against a real API. The band is labelled advisory and
# regressions are the human reviewer's call — revisit once the baseline has
# history.
#
# Usage:
#   ./bin/post-coverage-comment.sh <pr> <kcov-merged-dir> [--base <json>] [--dry-run]
#
# Env:
#   GITHUB_REPOSITORY   owner/repo (set by Actions; asked from gh otherwise)
#   COVERAGE_FLOOR      band floor,  default 30
#   COVERAGE_TARGET     band target, default 60

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../lib/common.sh"

require jq
require gh "install the GitHub CLI"

MARKER='<!-- coverage-report -->'
FLOOR="${COVERAGE_FLOOR:-30}"
TARGET="${COVERAGE_TARGET:-60}"

pr="${1:-}"; dir="${2:-}"; shift 2 || true
base_json="" dry=""
while [ $# -gt 0 ]; do
    case "$1" in
        --base)    base_json="${2:-}"; shift 2 ;;
        --dry-run) dry=1; shift ;;
        *) log_error "Unknown argument: $1" ;;
    esac
done
case "$pr" in ''|*[!0-9]*) log_error "Usage: $0 <pr> <kcov-merged-dir> [--base <json>] [--dry-run]";; esac
json="$dir/coverage.json"
[ -f "$json" ] || log_error "No coverage.json in '$dir' — did the kcov run produce output?"

repo="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

pct=$(jq -r '.percent_covered' "$json")
covered=$(jq -r '.covered_lines' "$json")
total=$(jq -r '.total_lines' "$json")

base_pct=""
if [ -n "$base_json" ] && [ -f "$base_json" ]; then
    base_pct=$(jq -r '.percent_covered // empty' "$base_json")
fi

# Blue = covered on the base too, green = added by this PR, red = lost by it.
# Emoji because GitHub comments allow no other coloured mark in markdown.
bar() {
    local pct="$1" base="$2" width=20 head b i out=""
    head=$(awk -v p="$pct" -v w="$width" 'BEGIN{printf "%d", (p/100*w)+0.5}')
    if [ -z "$base" ]; then
        for ((i=0;i<width;i++)); do [ "$i" -lt "$head" ] && out+="🟦" || out+="⬜"; done
    else
        b=$(awk -v p="$base" -v w="$width" 'BEGIN{printf "%d", (p/100*w)+0.5}')
        if [ "$head" -ge "$b" ]; then
            for ((i=0;i<width;i++)); do
                if   [ "$i" -lt "$b" ];    then out+="🟦"
                elif [ "$i" -lt "$head" ]; then out+="🟩"
                else out+="⬜"; fi
            done
        else
            for ((i=0;i<width;i++)); do
                if   [ "$i" -lt "$head" ]; then out+="🟦"
                elif [ "$i" -lt "$b" ];    then out+="🟥"
                else out+="⬜"; fi
            done
        fi
    fi
    printf '%s' "$out"
}

# Epsilon on the delta: a 0.02-point wobble printing "▼ -0.0" teaches readers
# to ignore the arrow.
delta() {
    local head="$1" base="$2"
    [ -z "$base" ] && { printf 'no baseline, first measured run'; return; }
    awk -v h="$head" -v b="$base" 'BEGIN{
        d = h - b
        if (d < 0.05 && d > -0.05) { printf "unchanged vs develop"; exit }
        printf "%s %+.1f vs develop", (d > 0 ? "▲" : "▼"), d
    }'
}

band() {
    local p="$1"
    awk -v p="$p" -v f="$FLOOR" -v t="$TARGET" 'BEGIN{
        if (p < f)      printf "🔴 **Below floor**: %.1f points under the %s%% line floor", f - p, f
        else if (p < t) printf "🟡 **Approaching target**: %.1f points below the %s%% line target", t - p, t
        else            printf "🟢 **At target**: the %s%% line target is met", t
    }'
}

body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT
{
    printf '%s\n' "$MARKER"
    printf '## 🧪 Coverage: %s%% of lines (%s)\n\n' "$pct" "$(delta "$pct" "$base_pct")"
    printf '%s\n\n' "$(bar "$pct" "$base_pct")"
    printf '**%s/%s lines**\n\n' "$covered" "$total"
    printf '%s\n\n' "$(band "$pct")"
    printf '<details>\n<summary>Per-file coverage (worst first)</summary>\n\n'
    printf '| File | Coverage | Lines |\n|---|---:|---:|\n'
    jq -r --arg root "$REPO_ROOT/" '
        .files
        | map(.percent_covered |= tonumber)
        | sort_by(.percent_covered)[]
        | "| `\(.file | sub("^" + $root; ""))` | \(.percent_covered)% | \(.covered_lines)/\(.total_lines) |"
    ' "$json"
    printf '\n</details>\n'
    printf '\n<sub>🔴 below %s · 🟡 below %s · 🟢 at target. Advisory, no gate: kcov under one suite on one OS undercounts by construction, so regressions are the reviewer'"'"'s call. Measured by kcov over the bats suite.</sub>\n' "$FLOOR" "$TARGET"
} > "$body_file"

if [ -n "$dry" ]; then
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
