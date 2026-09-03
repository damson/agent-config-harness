#!/usr/bin/env bats
#
# Tests for bin/setup.sh — verifies symlinks and skills are wired correctly.

load helpers/common

setup() {
    cd "$REPO_ROOT"
    setup_test_home
}

teardown() {
    teardown_test_home
}

@test "setup: creates ~/.claude/CLAUDE.md symlink" {
    run ./bin/setup.sh
    [ "$status" -eq 0 ]
    [ -L "$HOME/.claude/CLAUDE.md" ]
    [ "$(readlink "$HOME/.claude/CLAUDE.md")" = "$REPO_ROOT/user-dev/CLAUDE.md" ]
}

@test "setup: creates ~/.claude/preferences.md symlink" {
    ./bin/setup.sh >/dev/null
    [ -L "$HOME/.claude/preferences.md" ]
}

@test "setup: creates ~/.claude/user_tone_of_voice.md symlink" {
    ./bin/setup.sh >/dev/null
    [ -L "$HOME/.claude/user_tone_of_voice.md" ]
}

@test "setup: links every skill under user-dev/skills/" {
    ./bin/setup.sh >/dev/null
    while IFS= read -r skill_dir; do
        name=$(basename "$skill_dir")
        [ -L "$HOME/.claude/skills/$name" ]
        [ -e "$HOME/.claude/skills/$name" ]   # resolves
    done < <(list_skill_paths)
}

@test "setup: creates ~/workspace/mobile/CLAUDE.md symlink (personal Mobile layer)" {
    ./bin/setup.sh >/dev/null
    [ -L "$HOME/workspace/mobile/CLAUDE.md" ]
    [ -e "$HOME/workspace/mobile/CLAUDE.md" ]   # resolves
}

@test "setup: backs up a pre-existing real file before linking over it" {
    mkdir -p "$HOME/.claude"
    printf 'my own config\n' > "$HOME/.claude/CLAUDE.md"
    run ./bin/setup.sh
    [ "$status" -eq 0 ]
    # The link landed…
    [ -L "$HOME/.claude/CLAUDE.md" ]
    [ "$(readlink "$HOME/.claude/CLAUDE.md")" = "$REPO_ROOT/user-dev/CLAUDE.md" ]
    # …and the original content survived in a timestamped backup, with a warning.
    local backup
    backup=$(find "$HOME/.claude" -maxdepth 1 -name 'CLAUDE.md.bak.*' | head -1)
    [ -n "$backup" ]
    assert_contains "$(cat "$backup")" "my own config"
    assert_contains "$output" "$backup"
}

@test "setup: replaces a pre-existing own-repo symlink without creating a backup" {
    mkdir -p "$HOME/.claude"
    ln -s "$REPO_ROOT/user-dev/CLAUDE.md" "$HOME/.claude/preferences.md"   # stale but ours
    run ./bin/setup.sh
    [ "$status" -eq 0 ]
    [ -L "$HOME/.claude/preferences.md" ]
    [ "$(readlink "$HOME/.claude/preferences.md")" = "$REPO_ROOT/user-dev/preferences.md" ]
    local leftover
    leftover=$(find "$HOME/.claude" -maxdepth 1 -name 'preferences.md.bak.*')
    [ -z "$leftover" ]
}

@test "setup: refuses to repoint a symlink owned by another config repo" {
    mkdir -p "$HOME/.claude" "$HOME/other-config-repo/user-dev"
    echo "the real global rules" > "$HOME/other-config-repo/user-dev/CLAUDE.md"
    ln -s "$HOME/other-config-repo/user-dev/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
    run ./bin/setup.sh
    [ "$status" -ne 0 ]
    assert_contains "$output" "another config repo owns it"
    # the foreign link survives untouched
    [ "$(readlink "$HOME/.claude/CLAUDE.md")" = "$HOME/other-config-repo/user-dev/CLAUDE.md" ]
}

@test "setup: AGENT_SETUP_FORCE=1 takes over a foreign symlink" {
    mkdir -p "$HOME/.claude" "$HOME/other-config-repo/user-dev"
    ln -s "$HOME/other-config-repo/user-dev/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
    run env AGENT_SETUP_FORCE=1 ./bin/setup.sh
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/.claude/CLAUDE.md")" = "$REPO_ROOT/user-dev/CLAUDE.md" ]
}

@test "setup: refuses to repoint a skill link owned by another repo" {
    mkdir -p "$HOME/.claude/skills" "$HOME/other-config-repo/skills/refresh-domain-benchmark"
    ln -s "$HOME/other-config-repo/skills/refresh-domain-benchmark" \
          "$HOME/.claude/skills/refresh-domain-benchmark"
    run ./bin/setup.sh
    [ "$status" -ne 0 ]
    assert_contains "$output" "another config repo owns it"
}

@test "setup: fresh install creates no backup files" {
    ./bin/setup.sh >/dev/null 2>&1
    local leftover
    leftover=$(find "$HOME/.claude" -maxdepth 1 -name '*.bak.*')
    [ -z "$leftover" ]
}

@test "setup: is idempotent (runs twice without error)" {
    ./bin/setup.sh >/dev/null
    run ./bin/setup.sh
    [ "$status" -eq 0 ]
}

@test "setup: pre-push hook blocks both protected branches" {
    # Install first — without this the test reads whatever hook a previously
    # ordered test happened to leave behind, and passes on a stale copy.
    ./bin/setup.sh >/dev/null
    local hook
    hook="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path hooks)/pre-push"
    [ -x "$hook" ]
    run bash -c "echo 'refs/heads/develop a refs/heads/develop b' | '$hook'"
    [ "$status" -eq 1 ]
    run bash -c "echo 'refs/heads/main a refs/heads/main b' | '$hook'"
    [ "$status" -eq 1 ]
    run bash -c "echo 'refs/heads/x a refs/heads/feature/x b' | '$hook'"
    [ "$status" -eq 0 ]
}

@test "setup: installs the pre-push hook when run from a git worktree" {
    # In a worktree .git is a FILE and the hooks live in the common dir, so a
    # hardcoded "$REPO_ROOT/.git/hooks" matches nothing and the install is
    # skipped without a word. Everything here happens inside a throwaway clone
    # so the real repo's hook is never removed to make the assertion mean
    # something.
    # Build the fixture from the WORKING tree, not `git clone` — a clone carries
    # committed content, so it would test whatever setup.sh is at HEAD and pass
    # or fail regardless of the edit under test.
    # It carries TRACKED files only: `git add` a new bin/ script before running
    # this, or the fixture omits it and setup.sh fails inside the worktree.
    local src="$TEST_HOME/repo" wt="$TEST_HOME/wt"
    mkdir -p "$src"
    ( cd "$REPO_ROOT" && git ls-files -z | xargs -0 tar cf - ) | tar xf - -C "$src"
    git -C "$src" init -q
    git -C "$src" add -A
    git -C "$src" -c user.email=test@example.com -c user.name=test \
        commit -qm "fixture" >/dev/null
    git -C "$src" worktree add --detach --quiet "$wt" HEAD

    # Both preconditions, or the assertion below proves nothing: .git must be
    # the file form, and the clone must start with no hook to inherit.
    [ -f "$wt/.git" ]
    [ ! -e "$src/.git/hooks/pre-push" ]

    ( cd "$wt" && ./bin/setup.sh >/dev/null )

    [ -x "$src/.git/hooks/pre-push" ]
    run bash -c "echo 'refs/heads/main a refs/heads/main b' | '$src/.git/hooks/pre-push'"
    [ "$status" -eq 1 ]
}

@test "setup: completes with stdin closed and installs no external provider" {
    # setup.sh runs unattended in CI. The external-skills step must report and
    # move on, never prompt and never invoke a vendor CLI.
    . lib/common.sh
    run ./bin/setup.sh </dev/null
    [ "$status" -eq 0 ]
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        probe=$(get_external_probe "$id")
        [ ! -e "$probe" ] || { echo "setup.sh installed external provider $id"; return 1; }
    done < <(list_external_skills)
}

@test "setup: points at the just recipe for missing external skills" {
    run ./bin/setup.sh </dev/null
    [ "$status" -eq 0 ]
    assert_contains "$output" "just skills-install"
}
