#!/usr/bin/env bash
#
# AI Setup — Benchmark Report
#
# Reads all JSON score files in benchmarks/scores/ and prints a per-domain
# trend table to stdout. Useful for spotting score regressions over time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

require jq "brew install jq"

SCORES_DIR="$REPO_ROOT/benchmarks/scores"

if [ ! -d "$SCORES_DIR" ]; then
    log_info "No benchmark data yet. Run 'just eval' to score the domains."
    exit 0
fi

# Any non-dot files present?
has_data=0
for f in "$SCORES_DIR"/*.json; do
    [ -f "$f" ] || continue
    has_data=1
    break
done
if [ "$has_data" -eq 0 ]; then
    log_info "No benchmark data yet. Run 'just eval' to score the domains."
    exit 0
fi

# Collect domains found in score files.
#
# Two deliberate details, both about one corrupt file.
#
# `-exec ... \;` rather than `+`: batched, jq aborts at the first file it
# cannot parse and never reads the rest, and `find` hands them over in
# directory order, so a corrupt file silently swallows every valid record
# that happens to sit behind it. One jq per file costs a process each and
# confines the damage to the file that earned it.
#
# `|| true`: jq still exits non-zero for that one file, `find` passes it up,
# and under `set -e` the assignment killed the script here. The report became
# exit 1 with nothing printed at all, and the "No valid score files" message
# two lines down could never be reached.
domains=$(find "$SCORES_DIR" -name '*.json' -exec jq -r '.domain' {} \; 2>/dev/null | sort -u || true)

if [ -z "$domains" ]; then
    log_info "No valid score files found."
    exit 0
fi

# Render one table per domain.
for d in $domains; do
    printf '\n%s\n' "$d"
    printf '%s\n' "──────────────────────────────────────────────────────────────────"
    printf '%-12s %-9s %-9s %-10s %-12s %-8s %-6s %s\n' \
        "Date" "Clarity" "Concise" "Complete" "Consistent" "Action" "Total" "Grade"

    # Select files by the domain recorded IN the JSON, not by filename glob —
    # a glob like *-web.json also matches skill-web.json (any domain this one
    # is a suffix of). The glob itself iterates in lexicographic order, which
    # is date order for the timestamped stems.
    for f in "$SCORES_DIR"/*.json; do
        [ -f "$f" ] || continue
        [ "$(jq -r '.domain // empty' "$f" 2>/dev/null)" = "$d" ] || continue
        date=$(jq -r '.date' "$f" | cut -dT -f1)
        clarity=$(jq -r '.scores.clarity' "$f")
        concise=$(jq -r '.scores.conciseness' "$f")
        complete=$(jq -r '.scores.completeness' "$f")
        consistent=$(jq -r '.scores.consistency' "$f")
        action=$(jq -r '.scores.actionability' "$f")
        pct=$(jq -r '.percentage' "$f")
        grade=$(jq -r '.grade' "$f")
        printf '%-12s %-9s %-9s %-10s %-12s %-8s %-6s %s\n' \
            "$date" "$clarity" "$concise" "$complete" "$consistent" "$action" "${pct}%" "$grade"
    done
done
echo
