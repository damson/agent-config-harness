#!/usr/bin/env bash
#
# AI Setup — External Skill Installer
#
# Installs the third-party skill bundles registered in
# config/external-skills.conf. They ship with their own vendor CLI and are not
# vendored into user-dev/skills/ — see docs/external-skills.md.
#
# Usage:
#   ./bin/install-external-skills.sh            # prompt per provider (TTY only)
#   ./bin/install-external-skills.sh --list     # report status, install nothing
#   ./bin/install-external-skills.sh --yes      # install everything missing
#   ./bin/install-external-skills.sh --refresh  # re-run installed providers too
#   ./bin/install-external-skills.sh --only <id> [--yes] [--refresh]
#
# Installing is always optional. A provider whose CLI is absent is reported and
# skipped, never treated as a failure — that is the normal state in CI and on a
# fresh machine.
#
# WITHOUT --refresh an installed provider is left alone, which is what makes
# setup cheap to re-run. That is also how a bundle goes stale: the vendor
# installer is never invoked a second time, so it can sit frozen for months
# while upstream moves and still report a tick. --refresh is the way to run it
# again, and --list says how old each install is.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

mode="prompt"      # prompt | list | yes
only=""
refresh=0          # 1 = act on providers that are already installed

# An install older than this is reported as stale. Age is a proxy for drift and
# not drift itself, so this is a warning, never a failure, and it is overridable
# because a sensible interval is the vendor's business rather than ours.
STALE_DAYS="${EXTERNAL_SKILLS_STALE_DAYS:-30}"

while [ $# -gt 0 ]; do
    case "$1" in
        --list)  mode="list" ;;
        --yes|-y) mode="yes" ;;
        --refresh) refresh=1 ;;
        --only)
            shift
            [ $# -gt 0 ] || log_error "--only needs a provider id"
            only="$1"
            ;;
        --help|-h)
            sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) log_error "Unknown argument: $1 (try --help)" ;;
    esac
    shift
done

if [ -n "$only" ] && ! external_skill_exists "$only"; then
    log_error "Unknown provider: $only. Registered: $(list_external_skills | tr '\n' ' ')"
fi

# Whole days since <path> was last modified, or nothing if it cannot be read.
# BSD and GNU stat reject each other's flags, and a Linux box with coreutils
# from brew answers to -c, so try both rather than branching on uname.
age_days() {
    local m now
    m=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || return 1
    [ -n "$m" ] || return 1
    now=$(date +%s)
    printf '%s\n' $(( (now - m) / 86400 ))
}

# status <id> → prints one of: installed | stale | missing | tool-missing
#
# `stale` is still installed: the install path treats it as present unless
# --refresh is given, so a plain `--yes` never starts reinstalling things behind
# the user's back. It exists so that --list stops answering "installed" to a
# question nobody asked, which is whether the bundle is CURRENT.
status_of() {
    local id="$1" probe requires age
    probe=$(get_external_probe "$id")
    requires=$(get_external_requires "$id")
    if [ -e "$probe" ]; then
        age=$(age_days "$probe") || age=""
        if [ -n "$age" ] && [ "$age" -ge "$STALE_DAYS" ]; then
            printf 'stale\n'
        else
            printf 'installed\n'
        fi
    elif ! command -v "$requires" >/dev/null 2>&1; then
        printf 'tool-missing\n'
    else
        printf 'missing\n'
    fi
}

providers=()
while IFS= read -r id; do
    [ -n "$id" ] || continue
    [ -z "$only" ] || [ "$id" = "$only" ] || continue
    providers+=("$id")
done < <(list_external_skills)

# ── --list: report and exit ───────────────────────────────
if [ "$mode" = "list" ]; then
    log_info "── External skills ──"
    for id in "${providers[@]}"; do
        case "$(status_of "$id")" in
            installed)
                log_ok "$id: installed ($(get_external_probe "$id"))" ;;
            stale)
                log_warn "$id: installed $(age_days "$(get_external_probe "$id")") days ago — refresh with: $(get_external_install "$id")" ;;
            missing)
                log_info "$id: missing — install with: $(get_external_install "$id")" ;;
            tool-missing)
                log_info "$id: '$(get_external_requires "$id")' not on PATH — see $(get_external_docs "$id")" ;;
        esac
    done
    exit 0
fi

# ── No TTY and no --yes: never prompt, never install ──────
# bin/setup.sh calls this path, and setup runs unattended in CI.
if [ "$mode" = "prompt" ] && [ ! -t 0 ]; then
    pending=0
    stale=0
    for id in "${providers[@]}"; do
        case "$(status_of "$id")" in
            missing) pending=$((pending + 1)) ;;
            stale)   stale=$((stale + 1)) ;;
        esac
    done
    if [ "$pending" -gt 0 ]; then
        log_info "$pending external skill provider(s) not installed. Run 'just skills-install' to add them."
    fi
    # Said even when nothing is missing: a stale bundle is invisible precisely
    # because the thing that would have reported it says "installed".
    if [ "$stale" -gt 0 ]; then
        log_warn "$stale external skill provider(s) over $STALE_DAYS days old. Re-run with --refresh to update them."
    fi
    exit 0
fi

# ── Install ───────────────────────────────────────────────
installed=0
for id in "${providers[@]}"; do
    state=$(status_of "$id")
    verb="Install"
    case "$state" in
        installed|stale)
            if [ "$refresh" -eq 0 ]; then
                log_ok "$id: already installed"
                continue
            fi
            # Every registered installer overwrites in place, so re-running one
            # is how a bundle gets current. Nothing here removes a skill the
            # vendor has since retired: that file is in no catalogue any more,
            # so no installer will ever touch it again, and --list cannot see
            # it either. Those are the one case that needs a human.
            verb="Refresh"
            ;;
        tool-missing)
            log_info "$id: '$(get_external_requires "$id")' not on PATH — skipped. See $(get_external_docs "$id")"
            continue
            ;;
    esac

    cmd=$(get_external_install "$id")

    if [ "$mode" = "prompt" ]; then
        printf '%s %s? [y/N] ' "$verb" "$id"
        read -r answer
        case "$answer" in
            [yY]|[yY][eE][sS]) ;;
            *) log_info "$id: skipped"; continue ;;
        esac
    fi

    log_info "$id: running: $cmd"
    if bash -c "$cmd"; then
        log_ok "$id: $([ "$verb" = "Refresh" ] && printf refreshed || printf installed)"
        installed=$((installed + 1))
    else
        # A vendor CLI failing is the vendor's problem, not a setup failure.
        # Report it and carry on so one bad provider cannot block the rest.
        log_warn "$id: install command failed — see $(get_external_docs "$id")"
    fi
done

log_ok "External skills: $installed $([ "$refresh" -eq 1 ] && printf 'installed or refreshed' || printf 'installed') this run."
