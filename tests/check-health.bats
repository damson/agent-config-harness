#!/usr/bin/env bats
#
# Tests for bin/check-health.sh

load helpers/common

setup() {
    cd "$REPO_ROOT"
    setup_test_home
    # Establish a valid state: link everything we expect.
    mkdir -p "$HOME/.claude/skills"
    ln -sf "$REPO_ROOT/user-dev/CLAUDE.md"             "$HOME/.claude/CLAUDE.md"
    ln -sf "$REPO_ROOT/user-dev/preferences.md"        "$HOME/.claude/preferences.md"
    ln -sf "$REPO_ROOT/user-pers/user_tone_of_voice.md" "$HOME/.claude/user_tone_of_voice.md"
    ln -sf "$REPO_ROOT/user-pers/custom_instructions.md" "$HOME/.claude/custom_instructions.md"
    while IFS= read -r skill_dir; do
        ln -sfn "$skill_dir" "$HOME/.claude/skills/$(basename "$skill_dir")"
    done < <(list_skill_paths)
    # Link a ~/workspace/<domain>/CLAUDE.md for every workspace domain, driven by
    # the registry exactly as bin/setup.sh is, so adding a domain to
    # config/domains.conf cannot silently break this fixture.
    #
    # The helpers are read from a subshell that sources lib/common.sh: bats does
    # not source it into setup(), so calling list_domains here directly fails as
    # "command not found" and the loop quietly links nothing.
    while IFS= read -r _ws; do
        [ -f "$REPO_ROOT/$_ws/CLAUDE.md" ] || continue
        mkdir -p "$HOME/$_ws"
        ln -sf "$REPO_ROOT/$_ws/CLAUDE.md" "$HOME/$_ws/CLAUDE.md"
    done < <(cd "$REPO_ROOT" && . lib/common.sh >/dev/null 2>&1 && for _d in $(list_domains); do get_domain_workspace "$_d"; done | grep '^workspace/')
}

teardown() {
    teardown_test_home
}

@test "check-health: all systems nominal when links present" {
    run ./bin/check-health.sh
    [ "$status" -eq 0 ]
    assert_contains "$output" "All systems nominal"
}

@test "check-health: fails when CLAUDE.md link missing" {
    rm "$HOME/.claude/CLAUDE.md"
    run ./bin/check-health.sh
    [ "$status" -ne 0 ]
    assert_contains "$output" "MISSING"
}

@test "check-health: reports dangling symlink" {
    rm "$HOME/.claude/CLAUDE.md"
    ln -sf "/tmp/nonexistent-target-xyz" "$HOME/.claude/CLAUDE.md"
    run ./bin/check-health.sh
    [ "$status" -ne 0 ]
    assert_contains "$output" "DANGLING"
}

@test "check-health: lists all registered domains" {
    run ./bin/check-health.sh
    assert_contains "$output" "mobile"
    assert_contains "$output" "web-react"
    assert_contains "$output" "backend-node"
    assert_contains "$output" "data-extraction"
}

@test "check-health: absent external skills do not fail the run" {
    # External providers are installed per machine by a vendor CLI. $HOME is
    # isolated here, so none are present — check-health must still be nominal.
    . lib/common.sh
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        [ ! -e "$(get_external_probe "$id")" ]
    done < <(list_external_skills)

    run ./bin/check-health.sh
    [ "$status" -eq 0 ]
    assert_contains "$output" "All systems nominal"
}

@test "check-health: lists every registered external skill provider" {
    run ./bin/check-health.sh
    assert_contains "$output" "External skills"
    assert_contains "$output" "android-skills"
    assert_contains "$output" "impeccable"
}
