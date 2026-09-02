#!/usr/bin/env bats
#
# Tests for bin/git-stealth.sh — the 'git spull' / 'git scommit' helper.
#
# Behavioral tests run against a throwaway host repo with a local bare origin
# and a temp dir standing in for the config repo (via AGENT_CONFIG_ROOT), so
# nothing touches the real checkout or a real remote.

load helpers/common

SCRIPT="$REPO_ROOT/bin/git-stealth.sh"

setup() {
    cd "$REPO_ROOT"
    FIX=""
}

teardown() {
    if [ -n "${FIX:-}" ] && [ -d "$FIX" ]; then
        rm -rf "$FIX"
    fi
}

# Build: a fake config repo ($CFG), a bare origin, and a host clone ($HOST)
# holding one tracked file WITH A SPACE in its name, stealthed into $CFG.
# Physical paths throughout (pwd -P), because the script resolves symlink
# targets with readlink -f and mktemp on macOS hands out a symlinked /var path.
make_stealth_fixture() {
    FIX=$(cd "$(mktemp -d)" && pwd -P)

    CFG="$FIX/cfg"
    mkdir -p "$CFG"
    printf 'config content\n' >"$CFG/rules with spaces.md"

    git init -q --bare "$FIX/origin.git"
    git clone -q "$FIX/origin.git" "$FIX/host"
    HOST="$FIX/host"
    git -C "$HOST" config user.email test@example.com
    git -C "$HOST" config user.name test
    printf 'committed content\n' >"$HOST/my rules.md"
    git -C "$HOST" add "my rules.md"
    git -C "$HOST" commit -qm "init"
    git -C "$HOST" push -qu origin HEAD

    ln -sf "$CFG/rules with spaces.md" "$HOST/my rules.md"
    git -C "$HOST" update-index --skip-worktree "my rules.md"
}

@test "git-stealth: errors with usage when no action given" {
    run "$SCRIPT"
    [ "$status" -ne 0 ]
    assert_contains "$output" "Usage"
}

@test "git-stealth: errors on unknown action" {
    run "$SCRIPT" frobnicate
    [ "$status" -ne 0 ]
    assert_contains "$output" "Unknown action"
}

@test "git-stealth: runs on stock macOS bash 3.2 (env shebang, no declare -A)" {
    assert_starts_with "$(head -1 "$SCRIPT")" "#!/usr/bin/env bash"
    run grep -F 'declare -A' "$SCRIPT"
    [ "$status" -ne 0 ]
}

@test "git-stealth: no hardcoded literal branch prefix" {
    run grep -E 'branch_prefix="[A-Z]+"' "$SCRIPT"
    [ "$status" -ne 0 ]
}

@test "git-stealth: branch prefix is configurable with a neutral default" {
    grep -qF 'STEALTH_BRANCH_PREFIX:-TICKET' "$SCRIPT"
}

@test "git-stealth: pull round-trips a stealth filename with spaces" {
    make_stealth_fixture
    # Config and committed content agree, so this pull must be a pure
    # round-trip: no sync-back, symlink and skip-worktree restored.
    printf 'committed content\n' >"$CFG/rules with spaces.md"
    cd "$HOST"

    run env AGENT_CONFIG_ROOT="$CFG" "$SCRIPT" pull
    [ "$status" -eq 0 ]
    assert_contains "$output" "Stealth Pull complete"
    assert_not_contains "$output" "Remote update detected"

    # Re-stealthed: symlink back in place, pointing at the right target,
    # and hidden from git again.
    [ -L "my rules.md" ]
    [ "$(readlink "my rules.md")" = "$CFG/rules with spaces.md" ]
    assert_starts_with "$(git ls-files -v "my rules.md")" "S"
    # No remote change happened, so the config file is untouched.
    [ "$(cat "$CFG/rules with spaces.md")" = "committed content" ]
}

@test "git-stealth: pull syncs a remote update back to the config repo" {
    make_stealth_fixture

    # Push an update from a second clone so the pull has something to fetch.
    git clone -q "$FIX/origin.git" "$FIX/other"
    git -C "$FIX/other" config user.email test@example.com
    git -C "$FIX/other" config user.name test
    printf 'remote updated\n' >"$FIX/other/my rules.md"
    git -C "$FIX/other" commit -aqm "update"
    git -C "$FIX/other" push -q

    cd "$HOST"
    run env AGENT_CONFIG_ROOT="$CFG" "$SCRIPT" pull
    [ "$status" -eq 0 ]
    assert_contains "$output" "Remote update detected"

    # The remote content landed in the config repo, and the file is hidden again.
    [ "$(cat "$CFG/rules with spaces.md")" = "remote updated" ]
    [ -L "my rules.md" ]
    assert_starts_with "$(git ls-files -v "my rules.md")" "S"
}

@test "git-stealth: commit honors STEALTH_BRANCH_PREFIX and survives a missing glab" {
    make_stealth_fixture
    cd "$HOST"
    local orig_branch
    orig_branch=$(git branch --show-current)

    # PATH is cut down to the system dirs so glab (a brew/local install) is
    # absent; git, coreutils and shasum/sha256sum are still found. Sign-off
    # prompt gets "y", ticket prompt gets an empty line.
    run bash -c "printf 'y\n\n' | PATH=/usr/bin:/bin AGENT_CONFIG_ROOT='$CFG' STEALTH_BRANCH_PREFIX=OPS '$SCRIPT' commit -m 'stealth test'"
    [ "$status" -eq 0 ]
    assert_contains "$output" "'glab' not found"
    assert_contains "$output" "Stealth Commit complete"

    # Branch prefix came from the environment, not a hardcoded default.
    local new_branch
    new_branch=$(git for-each-ref --format='%(refname:short)' 'refs/heads/OPS/*')
    [ -n "$new_branch" ]
    # The materialized config content was committed on that branch.
    [ "$(git show "$new_branch:my rules.md")" = "config content" ]
    # And we are back on the original branch with the file hidden again.
    [ "$(git branch --show-current)" = "$orig_branch" ]
    [ -L "my rules.md" ]
    assert_starts_with "$(git ls-files -v "my rules.md")" "S"
}
