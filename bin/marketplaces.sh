#!/usr/bin/env bash
#
# AI Setup — install skills from the registered Claude Code marketplaces.
#
# Skills used to be vendored into this repo. A marketplace is the better home
# for any that are portable: one copy, versioned by its publisher, installable
# per theme. This script makes the set reproducible — the registry records which
# marketplaces and which plugins, so a fresh machine ends up with the same
# skills instead of whatever was remembered.
#
# Usage:
#   ./bin/marketplaces.sh status              # what is registered vs installed
#   ./bin/marketplaces.sh install             # add + install everything registered
#   ./bin/marketplaces.sh install <id>        # just one marketplace
#   ./bin/marketplaces.sh validate <id>       # structural check on its skills
#   ./bin/marketplaces.sh eval <id> [plugin]  # score its skills on the rubric
#
# Env:
#   MARKETPLACES_CONF   override the registry path
#
# Never installs during `just setup`: setup has to run unattended, and adding a
# marketplace clones from the network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

cmd="${1:-status}"

require_claude() {
    command -v claude >/dev/null 2>&1 \
        || log_error "The 'claude' CLI is not on PATH — install Claude Code first"
}

# Installed state lives in Claude Code's settings, NOT on disk: the plugin cache
# directory survives an uninstall, so a path probe reports installed forever.
# Ask the CLI instead.
plugin_installed() {
    claude plugin list 2>/dev/null | grep -qF "$1@$2"
}

# Plugin names a marketplace declares, read from its checked-out manifest.
declared_plugins() {
    local mp="$1" manifest
    manifest="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/$mp/.claude-plugin/marketplace.json"
    [ -f "$manifest" ] || return 1
    python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
print("\n".join(p["name"] for p in d.get("plugins",[])))' "$manifest"
}

# The plugins to act on: the registry list, or everything declared when it is `*`.
wanted_plugins() {
    local mp="$1" spec
    spec=$(get_marketplace_plugins "$mp")
    if [ "$spec" = "*" ]; then
        declared_plugins "$mp" || return 1
    else
        printf '%s\n' "$spec" | tr ',' '\n' | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
    fi
}

do_status() {
    local any=0
    for mp in $(list_marketplaces); do
        any=1
        log_info "marketplace: $mp  ($(get_marketplace_source "$mp"))"
        if ! command -v claude >/dev/null 2>&1; then
            log_warn "  claude CLI not on PATH — cannot report plugin state"
            continue
        fi
        if ! declared_plugins "$mp" >/dev/null 2>&1; then
            log_warn "  not added yet — run 'just marketplaces-install'"
            log_info "  docs: $(get_marketplace_docs "$mp")"
            continue
        fi
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            if plugin_installed "$p" "$mp"; then
                log_ok "  $p"
            else
                log_info "  $p not installed"
            fi
        done < <(wanted_plugins "$mp")
    done
    [ "$any" -eq 1 ] || log_info "No marketplaces registered in $MARKETPLACES_CONF"
}

do_install() {
    require_claude
    local only="${1:-}" targets
    if [ -n "$only" ]; then
        marketplace_exists "$only" || log_error "Unknown marketplace: $only"
        targets="$only"
    else
        targets=$(list_marketplaces)
    fi
    [ -n "$targets" ] || { log_info "Nothing registered."; return 0; }

    for mp in $targets; do
        log_info "Adding marketplace $mp"
        # Idempotent: re-adding an existing marketplace exits 0 and says so.
        claude plugin marketplace add "$(get_marketplace_source "$mp")" >/dev/null \
            || log_error "Could not add marketplace $mp"
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            if plugin_installed "$p" "$mp"; then
                log_ok "  $p already installed"
            else
                # --yes is required whenever stdout is not a TTY.
                claude plugin install "$p@$mp" --yes >/dev/null \
                    && log_ok "  installed $p" \
                    || log_warn "  failed to install $p"
            fi
        done < <(wanted_plugins "$mp")
    done
}

case "$cmd" in
    status)   do_status ;;
    install)  do_install "${2:-}" ;;
    validate) [ $# -ge 2 ] || log_error "validate needs a marketplace id"
              "$SCRIPT_DIR/validate-skills.sh" --marketplace "$2" ;;
    eval)     [ $# -ge 2 ] || log_error "eval needs a marketplace id"
              mp="$2"; only="${3:-}"
              cache="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/$mp"
              [ -d "$cache" ] || log_error "Marketplace '$mp' has no installed plugins at $cache"
              found=0
              # <cache>/<plugin>/<version>/skills — score each plugin's tree in turn.
              while IFS= read -r dir; do
                  plugin=$(basename "$(dirname "$(dirname "$dir")")")
                  [ -n "$only" ] && [ "$plugin" != "$only" ] && continue
                  found=1
                  log_info "── $mp/$plugin ──"
                  SKILLS_DIR="$dir" "$REPO_ROOT/evals/run-skill-eval.sh"
              done < <(find "$cache" -mindepth 3 -maxdepth 3 -type d -name skills | sort)
              [ "$found" -eq 1 ] || log_error "No installed skills matched${only:+ plugin '$only'} in '$mp'" ;;
    -h|--help) sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)        log_error "Unknown command: $cmd (try status, install, validate)" ;;
esac
