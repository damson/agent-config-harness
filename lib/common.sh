# shellcheck shell=bash
#
# AI Setup — Shared Library
#
# Sourced by every script in bin/ and evals/. Provides:
#   - REPO_ROOT detection (absolute, resolved once)
#   - Domain registry reader
#   - External skill registry reader
#   - Domain detection from project path
#   - Logging helpers (log_info, log_ok, log_warn, log_error)
#   - Dependency guard (require <tool>)
#
# Usage at the top of a script:
#   set -euo pipefail
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "$SCRIPT_DIR/../lib/common.sh"

# ── Environment ───────────────────────────────────────────
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_lib_dir/.." && pwd)"
DOMAINS_CONF="$REPO_ROOT/config/domains.conf"
EXTERNAL_SKILLS_CONF="$REPO_ROOT/config/external-skills.conf"

# ── Logging ───────────────────────────────────────────────
_use_color=1
[ -t 1 ] || _use_color=0

_color() {
    if [ "$_use_color" -eq 1 ]; then printf '\033[%sm' "$1"; fi
}
_reset() {
    if [ "$_use_color" -eq 1 ]; then printf '\033[0m'; fi
}

log_info()  { printf '%s%s%s %s\n' "$(_color '0;34')" "ℹ" "$(_reset)" "$*"; }
log_ok()    { printf '%s%s%s %s\n' "$(_color '0;32')" "✔" "$(_reset)" "$*"; }
log_warn()  { printf '%s%s%s %s\n' "$(_color '0;33')" "⚠" "$(_reset)" "$*" >&2; }
log_error() { printf '%s%s%s %s\n' "$(_color '0;31')" "✗" "$(_reset)" "$*" >&2; exit 1; }

# ── Dependency Guards ─────────────────────────────────────
# require <tool> [install hint]
require() {
    local tool="$1"
    local hint="${2:-}"
    if ! command -v "$tool" >/dev/null 2>&1; then
        if [ -n "$hint" ]; then
            log_error "Required tool '$tool' not found. Install: $hint"
        else
            log_error "Required tool '$tool' not found in PATH"
        fi
    fi
}

# ── Registry Reader ───────────────────────────────────────
# Each function trims whitespace; comments (#) and blank lines are ignored.

# Internal: emit each non-comment, non-blank line of domains.conf
_iter_registry() {
    [ -f "$DOMAINS_CONF" ] || log_error "Domain registry not found at $DOMAINS_CONF"
    # Strip leading/trailing whitespace; skip comments and blank lines
    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/  { next }
        { print }
    ' "$DOMAINS_CONF"
}

# list_domains → prints one domain name per line
list_domains() {
    _iter_registry | awk -F= '{
        gsub(/[[:space:]]/, "", $1)
        print $1
    }'
}

# get_domain_workspaces <domain> → prints every path the domain answers to, one
# per line, in registry order. The FIRST is canonical: the managed files live
# there. Any others are detection aliases — folder names a project may sit under,
# holding no config and not required to exist in this repo.
get_domain_workspaces() {
    local domain="$1"
    _iter_registry | awk -F'[=:]' -v d="$domain" '
        {
            gsub(/[[:space:]]/, "", $1)
            if ($1 == d) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
                n = split($2, parts, ",")
                for (i = 1; i <= n; i++) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                    if (parts[i] != "") print parts[i]
                }
                exit
            }
        }
    '
}

# get_domain_workspace <domain> → the canonical workspace path. Callers that
# read, write or score a domain's files want this one, never an alias.
get_domain_workspace() {
    get_domain_workspaces "$1" | head -1
}

# get_domain_files <domain> → prints repo-side (dest) filenames, one per line.
# Supports optional source>dest mapping: "AGENTS.md>sub/CLAUDE.md" emits "sub/CLAUDE.md".
get_domain_files() {
    local domain="$1"
    _iter_registry | awk -F'[=:]' -v d="$domain" '
        {
            gsub(/[[:space:]]/, "", $1)
            if ($1 == d) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
                n = split($3, parts, ",")
                for (i = 1; i <= n; i++) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                    if (index(parts[i], ">") > 0) {
                        split(parts[i], m, ">")
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", m[2])
                        print m[2]
                    } else {
                        print parts[i]
                    }
                }
                exit
            }
        }
    '
}

# get_domain_file_src <domain> <repo_file> → prints the project-side filename.
# Returns repo_file unchanged when no mapping is defined for it.
get_domain_file_src() {
    local domain="$1" repo_file="$2"
    _iter_registry | awk -F'[=:]' -v d="$domain" -v dst="$repo_file" '
        {
            gsub(/[[:space:]]/, "", $1)
            if ($1 == d) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
                n = split($3, parts, ",")
                for (i = 1; i <= n; i++) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                    if (index(parts[i], ">") > 0) {
                        split(parts[i], m, ">")
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", m[1])
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", m[2])
                        if (m[2] == dst) { print m[1]; exit }
                    } else {
                        if (parts[i] == dst) { print dst; exit }
                    }
                }
                print dst
                exit
            }
        }
    '
}

# domain_exists <domain> → 0 if found, 1 otherwise
domain_exists() {
    local domain="$1"
    list_domains | grep -qx "$domain"
}

# ── External Skill Registry ───────────────────────────────
# Lines are "<id> = <requires> :: <probe> :: <install> :: <docs>".
# Field 3 (<install>) may itself contain '=' and ':', so the id is split off on
# the FIRST '=' only and the remainder is split on '::'.

# Internal: emit each non-comment, non-blank line of external-skills.conf
_iter_external() {
    [ -f "$EXTERNAL_SKILLS_CONF" ] ||
        log_error "External skill registry not found at $EXTERNAL_SKILLS_CONF"
    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        { print }
    ' "$EXTERNAL_SKILLS_CONF"
}

# list_external_skills → prints one provider id per line
list_external_skills() {
    _iter_external | awk -F= '{
        gsub(/[[:space:]]/, "", $1)
        print $1
    }'
}

# Internal: _external_field <id> <n> → prints the nth '::' field for that id
_external_field() {
    local id="$1" n="$2"
    _iter_external | awk -v want="$id" -v n="$n" '
        {
            eq = index($0, "=")
            if (eq == 0) next
            key = substr($0, 1, eq - 1)
            gsub(/[[:space:]]/, "", key)
            if (key != want) next
            rest = substr($0, eq + 1)
            count = split(rest, f, /[[:space:]]*::[[:space:]]*/)
            if (n > count) exit
            val = f[n]
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
            print val
            exit
        }
    '
}

# get_external_requires <id> → command that must be on PATH
get_external_requires() { _external_field "$1" 1; }

# get_external_probe <id> → path that exists once installed ('~' expanded)
get_external_probe() {
    local probe
    probe=$(_external_field "$1" 2)
    printf '%s\n' "${probe/#\~/$HOME}"
}

# get_external_install <id> → install command, run verbatim
get_external_install() { _external_field "$1" 3; }

# get_external_docs <id> → documentation URL
get_external_docs() { _external_field "$1" 4; }

# external_skill_exists <id> → 0 if registered, 1 otherwise
external_skill_exists() {
    list_external_skills | grep -qx "$1"
}

# ── Domain Detection ──────────────────────────────────────
# detect_domain <project_path>
#
# Splits the path into components and checks each against every name a domain
# answers to: its own name, plus the leaf of each workspace path it registers.
# A component matches if the name appears as a substring of it (so "acme-mobile"
# matches "mobile", and a project under "web/" matches a domain that registers
# "workspace/web"). Two aliases of the SAME domain are not a conflict. Ambiguity
# — components matching two different domains — returns non-zero with an error.
detect_domain() {
    local path="$1"
    [ -n "$path" ] || { log_warn "detect_domain: empty path"; return 1; }

    # "<alias> <domain>" pairs: the domain name, plus the leaf of each EXTRA
    # workspace path. The canonical path's leaf is deliberately not an alias —
    # the domain name already covers it, and a canonical leaf that is a common
    # word (a domain rooted at "docs", say) would otherwise match every project
    # with a directory by that name and make real paths ambiguous.
    local aliases=""
    local d ws first
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        aliases="${aliases}${d} ${d}"$'\n'
        first=1
        while IFS= read -r ws; do
            [ -n "$ws" ] || continue
            if [ "$first" -eq 1 ]; then first=0; continue; fi
            aliases="${aliases}${ws##*/} ${d}"$'\n'
        done < <(get_domain_workspaces "$d")
    done < <(list_domains)

    # Split the path into components on '/'
    local components=()
    local IFS='/'
    read -r -a components <<<"$path"
    unset IFS

    # Longest alias first, so a specific one wins over a shorter one it contains
    # ("backend-node" before "node"). Matches collapse to their domain, so two
    # aliases of one domain record it once.
    local sorted_aliases
    sorted_aliases=$(printf '%s' "$aliases" | grep -v '^$' \
        | awk '{ print length($1), $0 }' | sort -rn | cut -d' ' -f2-)

    local matched=""
    local component alias_line alias owner
    for component in "${components[@]}"; do
        [ -n "$component" ] || continue
        while IFS= read -r alias_line; do
            [ -n "$alias_line" ] || continue
            alias="${alias_line%% *}"
            owner="${alias_line##* }"
            case "$component" in
                *"$alias"*)
                    case " $matched " in
                        *" $owner "*) ;;  # domain already recorded
                        *) matched="${matched}${matched:+ }$owner" ;;
                    esac
                    ;;
            esac
        done <<<"$sorted_aliases"
    done

    # Count tokens in matched
    local count=0
    [ -n "$matched" ] && count=$(printf '%s\n' "$matched" | wc -w | tr -d ' ')

    case "$count" in
        0) log_warn "detect_domain: no registered domain matched '$path'"; return 1 ;;
        1) printf '%s\n' "$matched"; return 0 ;;
        *) log_warn "detect_domain: ambiguous path '$path' matched: $matched"; return 1 ;;
    esac
}

# ── Skills ────────────────────────────────────────────────
# Emit the absolute path of every skill directory, one per line.
#
# A skill is any directory holding a SKILL.md. They sit either at the top level
# (user-dev/skills/<name>/) or grouped one level down in a container
# (user-dev/skills/<group>/<name>/) so a project-specific set stays together.
# A directory without a SKILL.md is a container to descend into, not a skill.
#
# Only these two depths are searched: the installed layout is FLAT
# (~/.claude/skills/<name>), so grouping is a source-tree convenience and the
# leaf name stays the skill's identity. That makes leaf names globally unique —
# tests/skills.bats enforces it, because a collision would silently overwrite
# one skill's symlink with another's.
list_skill_dirs() {
    local root="$REPO_ROOT/user-dev/skills"
    [ -d "$root" ] || return 0

    local dir nested
    for dir in "$root"/*/; do
        [ -d "$dir" ] || continue
        if [ -f "$dir/SKILL.md" ]; then
            printf '%s\n' "${dir%/}"
            continue
        fi
        for nested in "$dir"/*/; do
            [ -f "$nested/SKILL.md" ] || continue
            printf '%s\n' "${nested%/}"
        done
    done
}

# Pull the JSON object out of a model's reply, read from stdin.
#
# The reply is prose-shaped: the object may be wrapped in a ```json fence, or
# preceded by a sentence, or followed by one. Taking "first { to end of input"
# keeps the closing fence and every trailing word, and `jq` then rejects a
# response that was perfectly well formed — silently discarding the score.
#
# So: drop fence markers, then keep the span from the first line holding `{` to
# the last line holding `}`. Handles a single-line object, a pretty-printed one,
# and prose on either side.
extract_json_object() {
    sed '/^[[:space:]]*```/d' | awk '
        { line[NR] = $0
          if (!first && index($0, "{")) first = NR
          if (index($0, "}")) last = NR }
        END { if (!first || !last) exit 1
              for (i = first; i <= last; i++) print line[i] }
    '
}
