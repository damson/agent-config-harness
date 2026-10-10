#!/usr/bin/env bash
#
# AI Setup — validate the structure of a skills tree.
#
# The same four invariants the test suite enforces on this repo's own skills,
# extracted so they can be pointed at any skills directory — in particular the
# ones a marketplace installs, which arrive from someone else and are held to
# no standard on the way in.
#
# None of these stops a skill loading. That is the point: each one leaves a
# skill that works and is not the skill you wrote. `name:` is optional and
# sets the command the `/` menu shows, while the folder name goes on invoking
# the skill too, so a mismatch lists it under a name its directory never shows
# and gives up that name entirely to any command already holding it. An omitted
# `description:` falls back to the first non-empty line of the body, so the
# trigger is whatever that line happens to say; what an empty one does instead
# is documented nowhere. A missing `## When to STOP` removes what stops a skill
# firing on work it should decline. And a duplicate leaf name collides for
# personal and project skills, which share one flat namespace and resolve by
# priority, leaving the loser simply absent; plugin skills are namespaced
# `plugin:skill` and do not collide. See https://code.claude.com/docs/en/skills .
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
        # kcov-ignore-start
        NR == 1 && /^---[[:space:]]*$/ { infm = 1; next }
        infm && /^---[[:space:]]*$/    { exit }
        infm && $0 ~ "^" key ":" {
            sub("^" key ":[[:space:]]*", ""); gsub(/^["'"'"']|["'"'"']$/, "")
            print; exit
        }
    ' "$1"
    # kcov-ignore-end
}

declare -a seen_leaves=()
for p in "${skills[@]}"; do
    leaf=$(basename "$p")
    f="$p/SKILL.md"

    name=$(frontmatter_value "$f" name)
    if [ -z "$name" ]; then
        problem "$leaf: frontmatter has no 'name:'"
    elif [ "$name" != "$leaf" ]; then
        problem "$leaf: frontmatter name is '$name', so the / menu shows that and not the folder"
    fi

    # A description can be a folded block (description: >), so accept any
    # non-empty content on the key line OR on the lines that follow it.
    if ! awk '
        # kcov-ignore-start
        NR == 1 && /^---[[:space:]]*$/ { infm = 1; next }
        infm && /^---[[:space:]]*$/    { exit }
        infm && /^description:/        { started = 1
                                         sub(/^description:[[:space:]]*>?[[:space:]]*/, "")
                                         if (length($0)) { found = 1 } ; next }
        started && /^[a-zA-Z_-]+:/     { exit }
        started && NF                  { found = 1 }
        END { exit(found ? 0 : 1) }
        # kcov-ignore-end
    ' "$f"; then
        problem "$leaf: frontmatter 'description:' is missing or empty; an omitted one falls back to the first line of the body, and an empty one is undocumented"
    fi

    grep -qE '^## +(Procedure|Step [0-9])' "$f" \
        || problem "$leaf: no '## Procedure' or '## Step N' section"

    grep -qE '^## +When to STOP' "$f" \
        || problem "$leaf: no '## When to STOP' section"

    for s in ${seen_leaves[@]+"${seen_leaves[@]}"}; do
        [ "$s" = "$leaf" ] && problem "$leaf: duplicate leaf name; personal and project skills share one namespace, so one of these wins and the other is absent"
    done
    seen_leaves+=("$leaf")
done

if [ "$fail" -gt 0 ]; then
    log_error "$fail problem(s) across ${#skills[@]} skill(s) in $label"
fi
log_ok "${#skills[@]} skill(s) in $label pass all structural checks"
