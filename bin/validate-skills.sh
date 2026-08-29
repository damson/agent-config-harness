#!/usr/bin/env bash
#
# AI Setup — validate the structure of a skills tree.
#
# The same four invariants the test suite enforces on this repo's own skills,
# extracted so they can be pointed at any skills directory — in particular the
# ones a marketplace installs, which arrive from someone else and are held to
# no standard on the way in.
#
# A skill that trips any of these fails in a way that is quiet at install time
# and confusing later: the wrong `name:` makes a skill unaddressable, a missing
# `## When to STOP` is what stops a skill firing on work it should decline, and
# a duplicate leaf name silently shadows another skill because skills install
# FLAT into ~/.claude/skills/ and share one namespace.
#
# Usage:
#   ./bin/validate-skills.sh                      # this repo's user-dev/skills
#   ./bin/validate-skills.sh <dir>                # any skills tree
#   ./bin/validate-skills.sh --marketplace <id>   # every installed plugin of a marketplace
#
# Exits non-zero if any skill fails, after reporting all of them — a validator
# that stops at the first failure makes you run it once per problem.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

usage() { sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

roots=()
label=""
case "${1:-}" in
    -h|--help) usage 0 ;;
    --marketplace)
        [ $# -ge 2 ] || log_error "--marketplace needs a marketplace id"
        mp="$2"
        cache="$CLAUDE_DIR/plugins/cache/$mp"
        [ -d "$cache" ] || log_error "Marketplace '$mp' has no installed plugins at $cache"
        # <cache>/<plugin>/<version>/skills
        while IFS= read -r d; do roots+=("$d"); done < <(find "$cache" -mindepth 3 -maxdepth 3 -type d -name skills | sort)
        [ "${#roots[@]}" -gt 0 ] || log_error "No installed plugin of '$mp' ships a skills/ directory"
        label="marketplace '$mp'"
        ;;
    "")  roots=("$REPO_ROOT/user-dev/skills"); label="user-dev/skills" ;;
    *)   [ -d "$1" ] || log_error "Not a directory: $1"
         roots=("$1"); label="$1" ;;
esac

# Collect every skill directory: one containing a SKILL.md, at depth 1 (plain)
# or 2 (grouped under a container folder).
skills=()
for r in "${roots[@]}"; do
    while IFS= read -r p; do skills+=("$p"); done < <(
        find "$r" -mindepth 1 -maxdepth 2 -type d -exec test -f '{}/SKILL.md' \; -print | sort
    )
done

[ "${#skills[@]}" -gt 0 ] || log_error "No skills found under $label"

fail=0
problem() { log_warn "$1"; fail=$((fail + 1)); }

# Frontmatter is the first --- ... --- block; read a scalar key out of it.
frontmatter_value() {
    awk -v key="$2" '
        NR == 1 && /^---[[:space:]]*$/ { infm = 1; next }
        infm && /^---[[:space:]]*$/    { exit }
        infm && $0 ~ "^" key ":" {
            sub("^" key ":[[:space:]]*", ""); gsub(/^["'"'"']|["'"'"']$/, "")
            print; exit
        }
    ' "$1"
}

declare -a seen_leaves=()
for p in "${skills[@]}"; do
    leaf=$(basename "$p")
    f="$p/SKILL.md"

    name=$(frontmatter_value "$f" name)
    if [ -z "$name" ]; then
        problem "$leaf: frontmatter has no 'name:'"
    elif [ "$name" != "$leaf" ]; then
        problem "$leaf: frontmatter name is '$name' — it must match the folder name"
    fi

    # A description can be a folded block (description: >), so accept any
    # non-empty content on the key line OR on the lines that follow it.
    if ! awk '
        NR == 1 && /^---[[:space:]]*$/ { infm = 1; next }
        infm && /^---[[:space:]]*$/    { exit }
        infm && /^description:/        { started = 1
                                         sub(/^description:[[:space:]]*>?[[:space:]]*/, "")
                                         if (length($0)) { found = 1 } ; next }
        started && /^[a-zA-Z_-]+:/     { exit }
        started && NF                  { found = 1 }
        END { exit(found ? 0 : 1) }
    ' "$f"; then
        problem "$leaf: frontmatter 'description:' is missing or empty"
    fi

    grep -qE '^## +(Procedure|Step [0-9])' "$f" \
        || problem "$leaf: no '## Procedure' or '## Step N' section"

    grep -qE '^## +When to STOP' "$f" \
        || problem "$leaf: no '## When to STOP' section"

    for s in ${seen_leaves[@]+"${seen_leaves[@]}"}; do
        [ "$s" = "$leaf" ] && problem "$leaf: duplicate leaf name — skills install flat and would shadow each other"
    done
    seen_leaves+=("$leaf")
done

if [ "$fail" -gt 0 ]; then
    log_error "$fail problem(s) across ${#skills[@]} skill(s) in $label"
fi
log_ok "${#skills[@]} skill(s) in $label pass all structural checks"
