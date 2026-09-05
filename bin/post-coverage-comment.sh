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
if [ ! -f "$json" ]; then
    # kcov names its result directory after the traced binary and only
    # sometimes also leaves a kcov-merged, so a caller that points at the
    # merged path can be correct and still find nothing there. Accept exactly
    # one coverage.json below $dir. Several means per-child fragments, and
    # picking one would report a single traced child's lines as the whole
    # run's, so refuse rather than guess.
    found=$(find "$dir" -maxdepth 2 -name coverage.json 2>/dev/null | sort)
    # grep -c exits 1 on no matches, which would abort the script under set -e.
    count=$(printf '%s\n' "$found" | grep -c . || true)
    if [ "$count" -eq 1 ]; then
        json="$found"
        log_info "No coverage.json directly in '$dir'; using $json"
    elif [ "$count" -gt 1 ]; then
        log_error "Several coverage.json files under '$dir'; refusing to report one child as the run:
$found"
    fi
fi
[ -f "$json" ] || log_error "No coverage.json in '$dir' — did the kcov run produce output?"

# kcov roots the paths in its report at the checkout it measured. That is not
# necessarily $REPO_ROOT: under AGENT_CONFIG_ROOT that variable points at the
# config repo being managed rather than at the tree under test, so stripping it
# silently no-opped and every row rendered a full absolute path. Derive the
# prefix from the report itself, which is right by construction.
strip_root=$(jq -r '.files[].file' "$json" | awk '
    NR == 1 { p = $0; next }
    {
        # Shrink the candidate prefix a path component at a time until it is
        # one this file shares. String regexes, not /.../: the delimiter would
        # have to be escaped inside the bracket expression.
        while (p != "" && substr($0, 1, length(p)) != p) {
            sub("[^/]*/?$", "", p)
        }
    }
    END {
        # Back to a directory boundary, so a single-file report does not have
        # its filename eaten.
        if (p !~ "/$") sub("[^/]*$", "", p)
        print p
    }
')

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
# The baseline belongs to whichever branch the pull request merges into, and
# that is not always develop: a release pull request's base is main. Naming
# develop unconditionally is the failure this guards against, because the
# label is the part a reviewer reads: a figure correctly measured against main
# and captioned "vs develop" is a wrong answer wearing a right one's clothes.
# GITHUB_BASE_REF carries the base on every pull_request event. Outside one
# there is no base to name, so say that rather than assert a branch.
delta() {
    local head="$1" base="$2" label="${GITHUB_BASE_REF:-the base branch}"
    [ -z "$base" ] && { printf 'no baseline, first measured run'; return; }
    awk -v h="$head" -v b="$base" -v l="$label" 'BEGIN{
        # kcov-ignore-start
        d = h - b
        if (d < 0.05 && d > -0.05) { printf "unchanged vs %s", l; exit }
        printf "%s %+.1f vs %s", (d > 0 ? "▲" : "▼"), d, l
    }'
    # kcov-ignore-end
}

band() {
    local p="$1"
    awk -v p="$p" -v f="$FLOOR" -v t="$TARGET" 'BEGIN{
        # kcov-ignore-start
        if (p < f)      printf "🔴 **Below floor**: %.1f points under the %s%% line floor", f - p, f
        else if (p < t) printf "🟡 **Approaching target**: %.1f points below the %s%% line target", t - p, t
        else            printf "🟢 **At target**: the %s%% line target is met", t
    }'
    # kcov-ignore-end
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
    jq -r --arg root "$strip_root" '
        # kcov-ignore-start
        # ltrimstr, not sub: the prefix is a path, and sub would read a dot in
        # it as "any character".
        .files
        | map(.percent_covered |= tonumber)
        | sort_by(.percent_covered)[]
        | "| `\(.file | ltrimstr($root))` | \(.percent_covered)% | \(.covered_lines)/\(.total_lines) |"
    ' "$json"
    # kcov-ignore-end
    printf '\n</details>\n'
    printf '\n<sub>🔴 below %s · 🟡 below %s · 🟢 at target. Advisory, no gate: kcov under one suite on one OS undercounts by construction, so regressions are the reviewer'"'"'s call. Measured by kcov over the bats suite.</sub>\n' "$FLOOR" "$TARGET"
} > "$body_file"

if [ -n "$dry" ]; then
    cat "$body_file"
    exit 0
fi

# --paginate runs --jq once PER PAGE and concatenates the outputs, so a marker
# comment on any page but the first made this multi-line, the PATCH URL
# malformed, and the script exit non-zero with the comment never refreshed.
# Slurp every page into one document, then filter once.
mine=$(gh api "repos/$repo/issues/$pr/comments" --paginate \
    | jq -s --arg m "$MARKER" '[.[][] | select(.body | startswith($m))]')
count=$(printf '%s' "$mine" | jq 'length')

case "$count" in
    0)
        gh api -X POST "repos/$repo/issues/$pr/comments" -F body=@"$body_file" >/dev/null
        log_ok "Posted coverage comment on PR #$pr"
        ;;
    1)
        id=$(printf '%s' "$mine" | jq -r '.[0].id')
        gh api -X PATCH "repos/$repo/issues/comments/$id" -F body=@"$body_file" >/dev/null
        log_ok "Refreshed coverage comment on PR #$pr"
        ;;
    *)
        # Editing one of several in place is silent and unrecoverable: the
        # body it overwrites is gone. Stop and let a human pick.
        log_error "PR #$pr carries $count comments with the coverage marker; refusing to guess which to edit. Delete the extras first."
        ;;
esac
