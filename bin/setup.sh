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

# Link a file into place without destroying an adopter's existing config.
# A regular file at the destination is someone's real content: move it aside to
# a timestamped backup and say so. A symlink (whoever it points at) is just a
# previous wiring — replace it silently, as re-runs always have.
# A symlink into a DIFFERENT repo means this machine's live config is a
# consumer repo vendoring the harness. Repointing it here would silently swap
# real config for the shipped example templates — the run must be made from
# that repo instead (its own `just setup` is also the recovery).
# Ownership is judged on RESOLVED paths: readlink returns the stored string,
# which would let `$REPO_ROOT/../elsewhere` wear an owned prefix and would
# make an owned-but-relative target look foreign. Absolutize against the
# link's own directory and canonicalize the parent where it exists; a target
# whose parent is gone is judged as stored (and its dot-dots refused below).
resolve_link_target() {
    local dest="$1" target dir
    target="$(readlink "$dest")"
    case "$target" in
        /*) : ;;
        *) target="$(dirname "$dest")/$target" ;;
    esac
    if dir="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)"; then
        printf '%s/%s' "$dir" "$(basename "$target")"
    else
        printf '%s' "$target"
    fi
}

OWNED_REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
OWNED_HARNESS_ROOT="$(cd "$HARNESS_ROOT" && pwd -P)"

# link_is_owned <path> — true when <path> is a symlink whose RESOLVED target
# lies inside a tree this run owns. The single ownership predicate: every
# caller that decides whether it may write over, or delete, a link asks this,
# so the write path and the prune path can no longer disagree about what
# "ours" means.
link_is_owned() {
    local dest="$1" current
    [ -L "$dest" ] || return 1
    current="$(resolve_link_target "$dest")"
    case "$current" in
        # Dot-dots that survived resolution mean ownership cannot be proven.
        *"/../"*|*"/..") return 1 ;;
        "$OWNED_REPO_ROOT"/*|"$OWNED_HARNESS_ROOT"/*) return 0 ;;
    esac
    return 1
}

refuse_foreign_link() {
    local dest="$1" current
    [ -L "$dest" ] || return 0
    # Not `link_is_owned "$dest" && return 0`: when the test is false the
    # AND-list is what fails, and it would take the script down under set -e.
    if link_is_owned "$dest"; then return 0; fi
    current="$(resolve_link_target "$dest")"
    [ "${AGENT_SETUP_FORCE:-}" = "1" ] || log_error \
"$dest already links outside this repo ($current) — another config repo owns it.
Run 'just setup' from that repo, or re-run with AGENT_SETUP_FORCE=1 to take over."
}

link_file() {
    local src="$1" dest="$2" backup
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        backup="$dest.bak.$(date '+%Y%m%d-%H%M%S')"
        mv "$dest" "$backup"
        log_warn "Existing $dest moved to $backup"
    fi
    refuse_foreign_link "$dest"
    ln -sf "$src" "$dest"
}

# ── 1. Global links (user-dev = developer, user-pers = personal identity) ──
mkdir -p "$HOME/.claude"

link_file "$REPO_ROOT/user-dev/CLAUDE.md"      "$HOME/.claude/CLAUDE.md"
link_file "$REPO_ROOT/user-dev/preferences.md" "$HOME/.claude/preferences.md"
link_file "$REPO_ROOT/user-dev/statusline.sh"  "$HOME/.claude/statusline.sh"
chmod +x "$REPO_ROOT/user-dev/statusline.sh"
log_ok "Linked user-dev/* into ~/.claude/"

link_file "$REPO_ROOT/user-pers/user_tone_of_voice.md"  "$HOME/.claude/user_tone_of_voice.md"
link_file "$REPO_ROOT/user-pers/custom_instructions.md" "$HOME/.claude/custom_instructions.md"
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
    link_file "$REPO_ROOT/$_ws/CLAUDE.md" "$HOME/workspace/$_leaf/CLAUDE.md"
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
    refuse_foreign_link "$HOME/.claude/skills/$skill_name"
    ln -sfn "$skill_dir" "$HOME/.claude/skills/$skill_name"
    log_ok "Linked skill: $skill_name"
done < <(list_skill_dirs)

# Prune links left by a skill that was renamed or deleted here. Without this a
# rename leaves the old name behind pointing at a path that no longer exists,
# and the agent still lists it. Only dangling links into a tree this run owns
# are removed; anything pointing elsewhere is the user's own.
#
# Judged with link_is_owned, the same predicate the write path uses. Matching
# readlink's raw string instead, as this loop used to, missed every link that
# resolves into the owned tree without being spelled that way: one stored
# relative, or reaching it through an intermediate symlink. Those are exactly
# the shapes the write path accepts, so the two ends disagreed and a stale
# link survived every run.
for skill_link in "$HOME/.claude/skills"/*; do
    [ -L "$skill_link" ] || continue
    [ -e "$skill_link" ] && continue
    if link_is_owned "$skill_link"; then
        rm -f "$skill_link"
        log_ok "Pruned stale skill link: $(basename "$skill_link")"
    fi
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
#   cp <harness>/config/templates/claude-hooks.json .claude/settings.json
# (or merge if .claude/settings.json already exists).
if [ ! -f "$REPO_ROOT/.claude/settings.json" ]; then
    log_info "Optional: enable Claude Code hooks with:"
    # Printed for a human to run, so it has to be a path that exists from where
    # they are. In a consumer repo the template lives under the harness, not
    # under the repo being managed.
    log_info "  cp ${HARNESS_ROOT}/config/templates/claude-hooks.json .claude/settings.json"
fi

# ── 6. Append setup log ───────────────────────────────────
{
    printf '## Setup: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf -- '- Machine: %s\n' "$(hostname)"
    printf -- '- Path: %s\n' "$REPO_ROOT"
    printf -- '- Domains: %s\n\n' "$(list_domains | tr '\n' ' ')"
} >> "$LOG_FILE"

log_ok "Setup complete. Run 'just check' to verify."
