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
#   ./bin/install-external-skills.sh --only <id> [--yes]
#
# Installing is always optional. A provider whose CLI is absent is reported and
# skipped, never treated as a failure — that is the normal state in CI and on a
# fresh machine. Re-running installs nothing that is already present.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

mode="prompt"      # prompt | list | yes
only=""

while [ $# -gt 0 ]; do
    case "$1" in
        --list)  mode="list" ;;
        --yes|-y) mode="yes" ;;
        --only)
            shift
            [ $# -gt 0 ] || log_error "--only needs a provider id"
            only="$1"
            ;;
        --help|-h)
            sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) log_error "Unknown argument: $1 (try --help)" ;;
    esac
    shift
done

if [ -n "$only" ] && ! external_skill_exists "$only"; then
    log_error "Unknown provider: $only. Registered: $(list_external_skills | tr '\n' ' ')"
fi

# status <id> → prints one of: installed | missing | tool-missing
status_of() {
    local id="$1" probe requires
    probe=$(get_external_probe "$id")
    requires=$(get_external_requires "$id")
    if [ -e "$probe" ]; then
        printf 'installed\n'
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
    for id in "${providers[@]}"; do
        [ "$(status_of "$id")" = "missing" ] && pending=$((pending + 1))
    done
    if [ "$pending" -gt 0 ]; then
        log_info "$pending external skill provider(s) not installed. Run 'just skills-install' to add them."
    fi
    exit 0
fi

# ── Install ───────────────────────────────────────────────
installed=0
for id in "${providers[@]}"; do
    case "$(status_of "$id")" in
        installed)
            log_ok "$id: already installed"
            continue
            ;;
        tool-missing)
            log_info "$id: '$(get_external_requires "$id")' not on PATH — skipped. See $(get_external_docs "$id")"
            continue
            ;;
    esac

    cmd=$(get_external_install "$id")

    if [ "$mode" = "prompt" ]; then
        printf 'Install %s? [y/N] ' "$id"
        read -r answer
        case "$answer" in
            [yY]|[yY][eE][sS]) ;;
            *) log_info "$id: skipped"; continue ;;
        esac
    fi

    log_info "$id: running: $cmd"
    if bash -c "$cmd"; then
        log_ok "$id: installed"
        installed=$((installed + 1))
    else
        # A vendor CLI failing is the vendor's problem, not a setup failure.
        # Report it and carry on so one bad provider cannot block the rest.
        log_warn "$id: install command failed — see $(get_external_docs "$id")"
    fi
done

log_ok "External skills: $installed installed this run."
