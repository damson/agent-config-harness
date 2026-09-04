#!/usr/bin/env bats
#
# Tests for bin/impeccable-hooks.sh — the per-project design hook installer.

load helpers/common

setup() {
    cd "$REPO_ROOT"
    setup_test_home
}

teardown() {
    teardown_test_home
}

# Build a git repo under the leaf of a frontend domain's workspace path.
make_frontend_project() {
    local name="$1"
    local ws
    ws=$(cd "$REPO_ROOT" && . lib/common.sh >/dev/null 2>&1; get_domain_workspace "web-react")
    mkdir -p "$HOME/$ws/$name"
    ( cd "$HOME/$ws/$name" && git init -q . )
    printf '%s' "$HOME/$ws/$name"
}

@test "impeccable-hooks: --list finds a project under a frontend workspace" {
    make_frontend_project "demo-site" >/dev/null
    run ./bin/impeccable-hooks.sh --list
    [ "$status" -eq 0 ]
    assert_contains "$output" "demo-site"
    assert_contains "$output" "no hook"
}

@test "impeccable-hooks: --list reports a project that already has the hook" {
    local proj
    proj=$(make_frontend_project "wired-site")
    mkdir -p "$proj/.claude"
    printf '{"hooks":{"PostToolUse":[{"command":"npx impeccable detect"}]}}\n' \
        > "$proj/.claude/settings.local.json"
    run ./bin/impeccable-hooks.sh --list
    [ "$status" -eq 0 ]
    assert_contains "$output" "wired-site: hook present"
}

@test "impeccable-hooks: --list installs nothing" {
    local proj
    proj=$(make_frontend_project "untouched-site")
    run ./bin/impeccable-hooks.sh --list
    [ "$status" -eq 0 ]
    [ ! -e "$proj/.claude/settings.local.json" ]
}

@test "impeccable-hooks: a non-git directory is not treated as a project" {
    local ws
    ws=$(cd "$REPO_ROOT" && . lib/common.sh >/dev/null 2>&1; get_domain_workspace "web-react")
    mkdir -p "$HOME/$ws/just-a-folder"
    run ./bin/impeccable-hooks.sh --list
    [ "$status" -eq 0 ]
    assert_not_contains "$output" "just-a-folder"
}

@test "impeccable-hooks: unattended run never prompts and never installs" {
    local proj
    proj=$(make_frontend_project "ci-site")
    run bash -c "./bin/impeccable-hooks.sh < /dev/null"
    [ "$status" -eq 0 ]
    [ ! -e "$proj/.claude/settings.local.json" ]
}

@test "impeccable-hooks: rejects a path that is not a directory" {
    run ./bin/impeccable-hooks.sh /nope/not/here
    [ "$status" -ne 0 ]
}

@test "impeccable-hooks: --help prints the usage block" {
    run ./bin/impeccable-hooks.sh --help
    [ "$status" -eq 0 ]
    assert_contains "$output" "Usage:"
}

@test "impeccable-hooks: an unknown flag errors instead of being swallowed" {
    run ./bin/impeccable-hooks.sh --frobnicate
    [ "$status" -ne 0 ]
    assert_contains "$output" "Unknown argument"
}

@test "impeccable-hooks: --yes installs via npx into explicit paths only" {
    local proj wired stub
    proj=$(make_frontend_project "target-site")
    wired=$(make_frontend_project "already-wired")
    mkdir -p "$wired/.claude"
    printf '{"hooks":"npx impeccable detect"}\n' > "$wired/.claude/settings.local.json"

    # Stub npx: record where it ran; the pinned install must never hit npm.
    stub=$(mktemp -d)
    printf '#!/bin/sh\npwd >> "%s/npx.calls"\necho "$@" >> "%s/npx.calls"\n' \
        "$stub" "$stub" > "$stub/npx"
    chmod +x "$stub/npx"

    run env PATH="$stub:$PATH" ./bin/impeccable-hooks.sh --yes "$proj" "$wired"
    rc=$status
    calls=$(cat "$stub/npx.calls" 2>/dev/null || true)
    rm -rf "$stub"
    [ "$rc" -eq 0 ]
    assert_contains "$output" "target-site: hook installed"
    assert_contains "$output" "already-wired: hook already present"
    assert_contains "$output" "/impeccable init"
    # npx ran in the un-wired project, with the pinned version.
    assert_contains "$calls" "target-site"
    assert_contains "$calls" "impeccable@3.6.1 install"
    assert_not_contains "$calls" "already-wired"
}

@test "impeccable-hooks: a failing npx install warns without aborting" {
    local proj stub
    proj=$(make_frontend_project "broken-site")
    stub=$(mktemp -d)
    printf '#!/bin/sh\nexit 1\n' > "$stub/npx"
    chmod +x "$stub/npx"
    run env PATH="$stub:$PATH" ./bin/impeccable-hooks.sh --yes "$proj"
    rm -rf "$stub"
    [ "$status" -eq 0 ]
    assert_contains "$output" "install failed"
}
