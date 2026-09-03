#!/usr/bin/env bats
#
# Tests for bin/stealth.sh, bin/unstealth.sh, bin/materialize.sh — the three
# scripts that mutate a HOST repo (symlink swap + skip-worktree). Each test
# builds a throwaway git repo whose path matches the "mobile" example domain,
# so detect_domain resolves it against this repo's registry.

load helpers/common

setup() {
    TMP_BASE=$(mktemp -d -t stealth-host-XXXX)
    PROJECT="$TMP_BASE/acme-mobile"
    mkdir -p "$PROJECT"
    git -C "$PROJECT" init -q
    printf 'host repo content\n' > "$PROJECT/CLAUDE.md"
    git -C "$PROJECT" add CLAUDE.md
    git -C "$PROJECT" -c user.email=test@test.invalid -c user.name=test \
        commit -qm "init"
    SOURCE_FILE="$REPO_ROOT/workspace/mobile/CLAUDE.md"
}

teardown() {
    [ -n "${TMP_BASE:-}" ] && [ -d "$TMP_BASE" ] && rm -rf "$TMP_BASE"
}

# First column of `git ls-files -v` for the managed file:
# "H" = tracked normally, "S" = skip-worktree set.
tracked_flag() {
    git -C "$PROJECT" ls-files -v CLAUDE.md | cut -c1
}

# ── stealth.sh ────────────────────────────────────────────

@test "stealth: replaces tracked file with symlink and sets skip-worktree" {
    run "$REPO_ROOT/bin/stealth.sh" "$PROJECT" CLAUDE.md
    [ "$status" -eq 0 ]
    [ -L "$PROJECT/CLAUDE.md" ]
    [ "$(readlink "$PROJECT/CLAUDE.md")" = "$SOURCE_FILE" ]
    [ "$(tracked_flag)" = "S" ]
    # The symlink resolves to the workspace content
    diff "$PROJECT/CLAUDE.md" "$SOURCE_FILE"
}

@test "stealth: errors on nonexistent project path" {
    run "$REPO_ROOT/bin/stealth.sh" "/no/such/acme-mobile" CLAUDE.md
    [ "$status" -ne 0 ]
    assert_contains "$output" "not found"
}

@test "stealth: errors when the workspace has no such source file" {
    run "$REPO_ROOT/bin/stealth.sh" "$PROJECT" NO-SUCH-FILE.md
    [ "$status" -ne 0 ]
    assert_contains "$output" "does not exist"
    # and the host file was left alone
    [ ! -L "$PROJECT/CLAUDE.md" ]
}

@test "stealth: refuses an untracked target and leaves it untouched" {
    # An untracked file's content is not recoverable from git, so the
    # tracked check must run before any mutation: error out, leave the
    # file byte-identical, no symlink swap.
    printf 'untracked local rules\n' > "$PROJECT/.cursorrules"
    run "$REPO_ROOT/bin/stealth.sh" "$PROJECT" .cursorrules
    [ "$status" -ne 0 ]
    assert_contains "$output" "not tracked"
    [ ! -L "$PROJECT/.cursorrules" ]
    [ "$(cat "$PROJECT/.cursorrules")" = "untracked local rules" ]
}

# ── unstealth.sh ──────────────────────────────────────────

@test "unstealth: restores original content and clears skip-worktree" {
    "$REPO_ROOT/bin/stealth.sh" "$PROJECT" CLAUDE.md
    run "$REPO_ROOT/bin/unstealth.sh" "$PROJECT" CLAUDE.md
    [ "$status" -eq 0 ]
    [ ! -L "$PROJECT/CLAUDE.md" ]
    [ -f "$PROJECT/CLAUDE.md" ]
    grep -qF 'host repo content' "$PROJECT/CLAUDE.md"
    [ "$(tracked_flag)" = "H" ]
    # The host repo is left clean — safe to pull/merge/rebase
    [ -z "$(git -C "$PROJECT" status --porcelain)" ]
}

@test "unstealth: errors when the file is not tracked by the host repo" {
    run "$REPO_ROOT/bin/unstealth.sh" "$PROJECT" GHOST.md
    [ "$status" -ne 0 ]
}

# ── materialize.sh ────────────────────────────────────────

@test "materialize: stages workspace content as a real file, keeps stealth" {
    "$REPO_ROOT/bin/stealth.sh" "$PROJECT" CLAUDE.md
    run "$REPO_ROOT/bin/materialize.sh" "$PROJECT" CLAUDE.md
    [ "$status" -eq 0 ]
    # Index now holds the workspace content...
    [ "$(git -C "$PROJECT" show :CLAUDE.md)" = "$(cat "$SOURCE_FILE")" ]
    # ...as a regular file, not a symlink
    git -C "$PROJECT" ls-files -s -- CLAUDE.md | grep -q '^100644'
    # ...while the working tree is back to the stealth symlink, still hidden
    [ -L "$PROJECT/CLAUDE.md" ]
    [ "$(readlink "$PROJECT/CLAUDE.md")" = "$SOURCE_FILE" ]
    [ "$(tracked_flag)" = "S" ]
}

@test "materialize: errors when the target is not a stealth symlink" {
    run "$REPO_ROOT/bin/materialize.sh" "$PROJECT" CLAUDE.md
    [ "$status" -ne 0 ]
    assert_contains "$output" "not a stealth symlink"
    # and the tracked file was not touched
    [ ! -L "$PROJECT/CLAUDE.md" ]
    grep -qF 'host repo content' "$PROJECT/CLAUDE.md"
}
