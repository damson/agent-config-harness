#!/usr/bin/env bash
#
# AI Setup — Global Environment Configuration
#
# Links the centralised configs (user-dev/*) into the locations Claude, Cursor,
# and other agents expect, plus wires every skill under user-dev/skills/ into
# ~/.claude/skills/. Reports (but never installs) the third-party skill bundles
# registered in config/external-skills.conf. Also installs git aliases
# (spull/scommit) and a pre-push hook that blocks direct pushes to main and
# develop on this repo.
#
# Idempotent: safe to re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

LOG_FILE="$REPO_ROOT/SETUP_LOG.md"

log_info "Starting AI Setup..."

# ── 1. Global links (user-dev = developer, user-pers = personal identity) ──
mkdir -p "$HOME/.claude"

ln -sf "$REPO_ROOT/user-dev/CLAUDE.md"           "$HOME/.claude/CLAUDE.md"
ln -sf "$REPO_ROOT/user-dev/preferences.md"      "$HOME/.claude/preferences.md"
ln -sf "$REPO_ROOT/user-dev/statusline.sh"        "$HOME/.claude/statusline.sh"
chmod +x "$REPO_ROOT/user-dev/statusline.sh"
log_ok "Linked user-dev/* into ~/.claude/"

ln -sf "$REPO_ROOT/user-pers/user_tone_of_voice.md" "$HOME/.claude/user_tone_of_voice.md"
ln -sf "$REPO_ROOT/user-pers/custom_instructions.md" "$HOME/.claude/custom_instructions.md"
log_ok "Linked user-pers/* into ~/.claude/"

# Merge the statusLine key into ~/.claude/settings.json (preserve existing keys).
SETTINGS="$HOME/.claude/settings.json"
if command -v jq >/dev/null 2>&1; then
    [ -f "$SETTINGS" ] || printf '{}\n' >"$SETTINGS"
    tmp="$(mktemp)"
    jq '.statusLine = {"type":"command","command":"~/.claude/statusline.sh"}' \
        "$SETTINGS" >"$tmp" && mv "$tmp" "$SETTINGS"
    log_ok "Configured statusLine in ~/.claude/settings.json"
else
    log_info "jq not found — skipped statusLine wiring in settings.json"
fi

# ── 1b. Per-domain layers under ~/workspace/ ──────────────
# A domain's CLAUDE.md auto-loads when the working directory is inside its
# workspace folder. Driven by the registry, so adding a domain needs no edit
# here — only a line in config/domains.conf.
for _domain in $(list_domains); do
    _ws=$(get_domain_workspace "$_domain")          # canonical subdir, e.g. workspace/mobile
    case "$_ws" in workspace/*) ;; *) continue ;; esac   # skip non-workspace domains
    [ -f "$REPO_ROOT/$_ws/CLAUDE.md" ] || continue
    _leaf=${_ws#workspace/}
    mkdir -p "$HOME/workspace/$_leaf"
    ln -sf "$REPO_ROOT/$_ws/CLAUDE.md" "$HOME/workspace/$_leaf/CLAUDE.md"
    log_ok "Linked $_domain layer → ~/workspace/$_leaf/CLAUDE.md"
done
unset _domain _ws _leaf

# ── 2. Skills (every directory under user-dev/skills/) ────
mkdir -p "$HOME/.claude/skills"

# Grouped skills (user-dev/skills/<group>/<name>/) link in FLAT, under the leaf
# name — agents look for ~/.claude/skills/<name>/SKILL.md and do not descend.
while IFS= read -r skill_dir; do
    [ -n "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    ln -sfn "$skill_dir" "$HOME/.claude/skills/$skill_name"
    log_ok "Linked skill: $skill_name"
done < <(list_skill_dirs)

# Prune links left by a skill that was renamed or deleted here. Without this a
# rename leaves the old name behind pointing at a path that no longer exists,
# and the agent still lists it. Only dangling links INTO this repo's skills tree
# are removed — anything pointing elsewhere is the user's own.
for skill_link in "$HOME/.claude/skills"/*; do
    [ -L "$skill_link" ] || continue
    [ -e "$skill_link" ] && continue
    case "$(readlink "$skill_link")" in
        "$REPO_ROOT/user-dev/skills"/*)
            rm -f "$skill_link"
            log_ok "Pruned stale skill link: $(basename "$skill_link")"
            ;;
    esac
done

# ── 2b. External skills (third-party, vendor-installed) ───
# Reports what is missing and stops there. Setup must stay unattended-safe: the
# installer only prompts on a TTY, and only `just skills-install` installs.
"$SCRIPT_DIR/install-external-skills.sh" </dev/null

# ── 3. Git aliases (stealth pull / stealth commit) ────────
git config --global alias.spull  "!$HARNESS_ROOT/bin/git-stealth.sh pull"
git config --global alias.scommit "!$HARNESS_ROOT/bin/git-stealth.sh commit"
log_ok "Configured git aliases: spull, scommit"

# ── 4. Pre-push guard on this repo (block direct push to main/develop) ─
# Ask git where the hooks live rather than assuming "$REPO_ROOT/.git/hooks":
# inside a worktree .git is a FILE and the hooks sit in the common dir, so the
# hardcoded path matched nothing and the old `[ -d ]` guard skipped the install
# in silence — on a fresh clone set up from a worktree, no guard at all.
if HOOK_DIR="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)"; then
    mkdir -p "$HOOK_DIR"
    cat >"$HOOK_DIR/pre-push" <<'HOOK_EOF'
#!/usr/bin/env bash
# ai-setup: refuse direct pushes to the protected branches.
# develop integrates feature work; main carries releases. Both land via PR.
while read -r local_ref local_sha remote_ref remote_sha; do
    case "$remote_ref" in
        refs/heads/main|refs/heads/develop)
            echo "✗ Direct pushes to ${remote_ref#refs/heads/} are blocked. Open a PR instead." >&2
            exit 1
            ;;
    esac
done
exit 0
HOOK_EOF
    chmod +x "$HOOK_DIR/pre-push"
    log_ok "Installed pre-push hook (blocks direct push to main/develop)"
else
    log_warn "Not a git repository — skipped the pre-push hook (main/develop are unguarded here)"
fi

# ── 5. Claude Code hooks (opt-in) ─────────────────────────
# We don't auto-install hooks because they modify agent behavior. If the user
# wants the in-session validation loop, they can run:
#   cp config/templates/claude-hooks.json .claude/settings.json
# (or merge if .claude/settings.json already exists).
if [ ! -f "$REPO_ROOT/.claude/settings.json" ]; then
    log_info "Optional: enable Claude Code hooks with:"
    log_info "  cp config/templates/claude-hooks.json .claude/settings.json"
fi

# ── 6. Append setup log ───────────────────────────────────
{
    printf '## Setup: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf -- '- Machine: %s\n' "$(hostname)"
    printf -- '- Path: %s\n' "$REPO_ROOT"
    printf -- '- Domains: %s\n\n' "$(list_domains | tr '\n' ' ')"
} >> "$LOG_FILE"

log_ok "Setup complete. Run 'just check' to verify."
