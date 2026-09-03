#!/usr/bin/env bash
#
# AI Setup — impeccable per-project design hook
#
# The impeccable SKILL installs globally (see install-external-skills.sh). Its
# design-detector HOOK does not: it is written per project AND per machine, into
# the gitignored .claude/settings.local.json. So a project you cloned, or a
# teammate's checkout, has the skill but no hook until this runs there.
#
# Usage:
#   ./bin/impeccable-hooks.sh                 # every frontend project found (prompts)
#   ./bin/impeccable-hooks.sh --list          # report status, change nothing
#   ./bin/impeccable-hooks.sh --yes           # install without prompting
#   ./bin/impeccable-hooks.sh <path> [<path>] # only these projects
#
# "Frontend project" is not hardcoded: a domain counts when its own guide tells
# the reader to use impeccable, and projects are its workspace folders under
# $HOME. Adding the rule to another domain's CLAUDE.md brings it in here too.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

mode="prompt"
paths=()

while [ $# -gt 0 ]; do
    case "$1" in
        --list)   mode="list" ;;
        --yes|-y) mode="yes" ;;
        --help|-h)
            sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*) log_error "Unknown argument: $1 (try --help)" ;;
        *)  paths+=("$1") ;;
    esac
    shift
done

# ── Which domains want impeccable ─────────────────────────
# Read it from each domain's own guide rather than keeping a second list here.
frontend_domains() {
    local d ws guide
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        ws=$(get_domain_workspace "$d")
        guide="$REPO_ROOT/$ws/CLAUDE.md"
        [ -f "$guide" ] || continue
        grep -qi 'impeccable' "$guide" && printf '%s\n' "$d"
    done < <(list_domains)
}

# ── Candidate projects ────────────────────────────────────
# Every immediate child of ~/<workspace-path> that is a git repo. Registry paths
# are repo-relative (workspace/web-react); the same leaf under $HOME is where the
# real projects live, which is the convention `just setup` already links against.
discover_projects() {
    local d ws proj
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        while IFS= read -r ws; do
            [ -n "$ws" ] || continue
            [ -d "$HOME/$ws" ] || continue
            for proj in "$HOME/$ws"/*/; do
                [ -d "$proj/.git" ] || [ -f "$proj/.git" ] || continue
                printf '%s\n' "${proj%/}"
            done
        done < <(get_domain_workspaces "$d")
    done < <(frontend_domains)
}

has_hook() {
    local settings="$1/.claude/settings.local.json"
    [ -f "$settings" ] && grep -qi 'impeccable' "$settings"
}

install_hook() {
    local proj="$1"
    log_info "Installing impeccable hook in $proj"
    # Version pinned for supply-chain safety — keep in lockstep with the
    # impeccable entry in config/external-skills.conf.
    ( cd "$proj" && npx --yes impeccable@3.6.1 install )
}

# ── Resolve targets ───────────────────────────────────────
targets=()
if [ "${#paths[@]}" -gt 0 ]; then
    for p in "${paths[@]}"; do
        [ -d "$p" ] || log_error "Not a directory: $p"
        targets+=("$(cd "$p" && pwd)")
    done
else
    while IFS= read -r p; do
        [ -n "$p" ] && targets+=("$p")
    done < <(discover_projects)
fi

if [ "${#targets[@]}" -eq 0 ]; then
    log_warn "No frontend projects found. Pass a path explicitly, or check that a domain guide mentions impeccable."
    exit 0
fi

# ── --list ────────────────────────────────────────────────
if [ "$mode" = "list" ]; then
    log_info "── impeccable design hook ──"
    for proj in "${targets[@]}"; do
        if has_hook "$proj"; then
            log_ok "$(basename "$proj"): hook present"
        else
            log_info "$(basename "$proj"): no hook — run 'just impeccable-hooks'"
        fi
    done
    exit 0
fi

if ! command -v npx >/dev/null 2>&1; then
    log_warn "npx not on PATH — cannot install. See docs/external-skills.md."
    exit 0
fi

# Unattended and not --yes: report only. setup.sh calls this path in CI.
if [ "$mode" = "prompt" ] && [ ! -t 0 ]; then
    for proj in "${targets[@]}"; do
        has_hook "$proj" || log_info "$(basename "$proj"): no impeccable hook — run 'just impeccable-hooks'"
    done
    exit 0
fi

installed=0
for proj in "${targets[@]}"; do
    if has_hook "$proj"; then
        log_ok "$(basename "$proj"): hook already present"
        continue
    fi
    if [ "$mode" = "prompt" ]; then
        printf 'Install the impeccable hook in %s? [y/N] ' "$(basename "$proj")"
        read -r reply </dev/tty || reply=""
        case "$reply" in [yY]*) ;; *) log_info "skipped $(basename "$proj")"; continue ;; esac
    fi
    if install_hook "$proj"; then
        installed=$((installed + 1))
        log_ok "$(basename "$proj"): hook installed"
    else
        log_warn "$(basename "$proj"): install failed — see the output above"
    fi
done

if [ "$installed" -gt 0 ]; then
    log_info "Run '/impeccable init' once inside a session in each project — it writes the"
    log_info "PRODUCT.md and DESIGN.md brief the skill reads on every later run, and it is a"
    log_info "slash command, so it cannot be scripted from here."
fi
