#!/usr/bin/env bash
#
# SessionStart hook: name the domains a project belongs to by what it contains.
#
# A domain's CLAUDE.md loads by itself only for a session started inside its
# folder under ~/workspace/. A project kept anywhere else, or one spanning two
# stacks, would read none of it. This hook reads the session's working
# directory from the hook payload, checks the project against
# config/domain-signals.conf, and prints the files to read for every domain
# that matches and is not already loaded by folder. SessionStart adds what a
# hook prints to the session's context.
#
# A hook must never break a session: anything unexpected ends it silently with
# status 0, and printing nothing is the answer for "no match".
#
# Usage (wired by setup.sh into ~/.claude/settings.json):
#   AGENT_CONFIG_ROOT=<config repo> session-domains.sh < hook-payload.json

set -uo pipefail
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
# The registry readers call log_error, which exits; a missing registry is "no
# domains" here, so check for it before anything can reach them.
[ -f "${AGENT_CONFIG_ROOT:-$SCRIPT_DIR/..}/config/domain-signals.conf" ] || exit 0
[ -f "${AGENT_CONFIG_ROOT:-$SCRIPT_DIR/..}/config/domains.conf" ] || exit 0
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh" 2>/dev/null || exit 0

payload=$(cat 2>/dev/null) || payload=""
cwd=""
if command -v jq >/dev/null 2>&1; then
    cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
fi
[ -n "$cwd" ] || cwd="$PWD"
[ -d "$cwd" ] || exit 0

# The project is the repository the session sits in, or the folder itself.
project=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || project="$cwd"
project=$(cd "$project" 2>/dev/null && pwd -P) || exit 0

# The config repo describes the domains; it is not a project of any of them.
[ "$project" = "$(cd "$REPO_ROOT" && pwd -P)" ] && exit 0

# True when the session already sits under a folder that loads this domain's
# CLAUDE.md, canonical or alias, so naming it again would only repeat it. The
# folder existing is not enough: an alias folder holds projects long before
# setup links the domain's CLAUDE.md into it.
loaded_by_folder() {
    local domain="$1" ws here
    here=$(cd "$cwd" && pwd -P)
    while IFS= read -r ws; do
        case "$ws" in workspace/*) ;; *) continue ;; esac
        [ -f "$HOME/$ws/CLAUDE.md" ] || continue
        case "$here/" in "$(cd "$HOME/$ws" && pwd -P)/"*) return 0 ;; esac
    done < <(get_domain_workspaces "$domain")
    return 1
}

lines=""
while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    project_matches_domain "$project" "$domain" || continue
    loaded_by_folder "$domain" && continue
    ws=$(get_domain_workspace "$domain") || continue
    files=""
    [ -f "$REPO_ROOT/$ws/CLAUDE.md" ] && files="$REPO_ROOT/$ws/CLAUDE.md"
    while IFS= read -r f; do
        case "$f" in ""|CLAUDE.md|*/*) continue ;; esac
        [ -f "$REPO_ROOT/$ws/$f" ] && files="$files${files:+, }$REPO_ROOT/$ws/$f"
    done < <(get_domain_files "$domain")
    [ -n "$files" ] && lines="$lines- $domain: $files"$'\n'
done < <(list_signal_domains)

[ -n "$lines" ] || exit 0
printf 'This project matches these domains by what it contains, not by where it sits. Read each file before designing or reviewing a change here; a project CLAUDE.md still wins where it differs:\n%s' "$lines"
exit 0
