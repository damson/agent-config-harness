#!/usr/bin/env bats
#
# Tests for bin/sync-back.sh — focused on detection + no-op behavior.
# Full PR creation is not tested here (would require remote access).

load helpers/common

setup() {
    cd "$REPO_ROOT"
}

@test "sync-back: errors on missing project path" {
    run ./bin/sync-back.sh
    [ "$status" -ne 0 ]
    assert_contains "$output" "Usage"
}

@test "sync-back: errors on nonexistent path" {
    run ./bin/sync-back.sh "/no/such/path/exists/here-xyz"
    [ "$status" -ne 0 ]
    assert_contains "$output" "not found"
}

@test "sync-back: errors on unknown domain" {
    local fake_project
    fake_project=$(mktemp -d)
    mkdir -p "$fake_project/unrelated-domain-xyz"
    run ./bin/sync-back.sh "$fake_project/unrelated-domain-xyz"
    [ "$status" -ne 0 ]
    rm -rf "$fake_project"
}

@test "sync-back: wires a post-PR benchmark comment via gh and glab" {
    # Static check: the script must contain the PR-comment branch for both tools
    # and must honor AI_SETUP_SKIP_EVAL so CI runs don't hit the Claude CLI.
    grep -q 'gh pr comment'    ./bin/sync-back.sh
    grep -q 'glab mr note'     ./bin/sync-back.sh
    grep -q 'AI_SETUP_SKIP_EVAL' ./bin/sync-back.sh
}

@test "sync-back: no-op when files match" {
    # Set up a fake project that mirrors the workspace exactly.
    # mobile domain maps AGENTS.md (project) → project/CLAUDE.md (repo), so the
    # project must have AGENTS.md with the same content as repo's project/CLAUDE.md.
    local tmp fake_project
    tmp=$(mktemp -d)
    fake_project="$tmp/acme-mobile"
    mkdir -p "$fake_project"
    cp "$REPO_ROOT/workspace/mobile/project/CLAUDE.md" "$fake_project/AGENTS.md"
    cp "$REPO_ROOT/workspace/mobile/CLAUDE.md"      "$fake_project/CLAUDE.md"
    cp "$REPO_ROOT/workspace/mobile/.cursorrules"    "$fake_project/.cursorrules"

    run ./bin/sync-back.sh "$fake_project"
    [ "$status" -eq 0 ]
    assert_contains "$output" "Nothing to sync"
    rm -rf "$tmp"
}

@test "sync-back: opens PRs against develop, not main" {
    # Pins the gitflow base. Without this, flipping the base back to main is
    # invisible to the suite — every other sync-back test is content-agnostic
    # about which branch the PR targets.
    grep -q 'gh pr create --base develop'          ./bin/sync-back.sh
    grep -q 'glab mr create --target-branch develop' ./bin/sync-back.sh
    ! grep -qE '(--base|--target-branch) main' ./bin/sync-back.sh
}
