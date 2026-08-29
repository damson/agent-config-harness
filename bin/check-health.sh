#!/usr/bin/env bash
#
# AI Setup — Health Check
#
# Verifies:
#   - Global ~/.claude/* links exist and resolve
#   - Every registered domain has its workspace folder
#   - Every managed file per domain exists at the registry location
#   - Skills under user-dev/skills/ are linked into ~/.claude/skills/
#   - External skill providers (informational only — see below)
#
# Exits non-zero on any failure. External skills are deliberately excluded from
# that count: they are optional, machine-local, and absent in CI by design.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

errors=0

check_link() {
    local link="$1"
    local description="$2"
    if [ -L "$link" ]; then
        if [ -e "$link" ]; then
            log_ok "$description"
        else
            log_warn "$description: DANGLING ($link → $(readlink "$link"))"
            errors=$((errors + 1))
        fi
    elif [ -e "$link" ]; then
        log_warn "$description: exists but is not a symlink ($link)"
    else
        log_warn "$description: MISSING ($link)"
        errors=$((errors + 1))
    fi
}

check_file() {
    local file="$1"
    local description="$2"
    if [ -e "$file" ]; then
        log_ok "$description"
    else
        log_warn "$description: MISSING ($file)"
        errors=$((errors + 1))
    fi
}

log_info "── Global links (~/.claude/) ──"
check_link "$HOME/.claude/CLAUDE.md"           "user-dev/CLAUDE.md → ~/.claude/CLAUDE.md"
check_link "$HOME/.claude/preferences.md"      "user-dev/preferences.md → ~/.claude/preferences.md"
check_link "$HOME/.claude/user_tone_of_voice.md" "user-pers/user_tone_of_voice.md → ~/.claude/user_tone_of_voice.md"
check_link "$HOME/.claude/custom_instructions.md" "user-pers/custom_instructions.md → ~/.claude/custom_instructions.md"
# Per-domain layers under ~/workspace/, driven by the registry so adding a
# domain needs no edit here. Mirrors the loop in bin/setup.sh.
for _domain in $(list_domains); do
    _ws=$(get_domain_workspace "$_domain")
    case "$_ws" in workspace/*) ;; *) continue ;; esac
    [ -f "$REPO_ROOT/$_ws/CLAUDE.md" ] || continue
    _leaf=${_ws#workspace/}
    check_link "$HOME/workspace/$_leaf/CLAUDE.md" "$_domain layer → ~/workspace/$_leaf/CLAUDE.md"
done
unset _domain _ws _leaf

log_info "── Skills ──"
if [ -d "$REPO_ROOT/user-dev/skills" ]; then
    while IFS= read -r skill_dir; do
        [ -n "$skill_dir" ] || continue
        skill_name=$(basename "$skill_dir")
        check_link "$HOME/.claude/skills/$skill_name" "skill: $skill_name"
    done < <(list_skill_dirs)
else
    log_warn "user-dev/skills directory missing"
fi

log_info "── External skills (optional) ──"
while IFS= read -r ext; do
    [ -n "$ext" ] || continue
    probe=$(get_external_probe "$ext")
    if [ -e "$probe" ]; then
        log_ok "external skill: $ext"
    else
        # Informational: does NOT increment errors. These are installed by a
        # vendor CLI per machine, so absence is a normal state, not a fault.
        log_info "external skill: $ext not installed — 'just skills-install'"
    fi
done < <(list_external_skills)

log_info "── Domains ──"
while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    ws=$(get_domain_workspace "$domain")
    if [ -d "$REPO_ROOT/$ws" ]; then
        log_ok "domain '$domain' workspace: $ws"
    else
        log_warn "domain '$domain' workspace MISSING: $ws"
        errors=$((errors + 1))
        continue
    fi
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        check_file "$REPO_ROOT/$ws/$f" "  $domain/$f"
    done < <(get_domain_files "$domain")
done < <(list_domains)

echo
if [ "$errors" -eq 0 ]; then
    log_ok "All systems nominal."
    exit 0
else
    log_warn "Found $errors issue(s). Run 'just setup' to repair links."
    exit 1
fi
