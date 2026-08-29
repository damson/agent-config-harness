#!/usr/bin/env bats
#
# Tests for bin/on-config-edit.sh — the PostToolUse hook handler.

load helpers/common

setup() {
    cd "$REPO_ROOT"
    setup_test_home
    mkdir -p "$HOME/.claude/skills"
    ln -sf "$REPO_ROOT/user-dev/CLAUDE.md"             "$HOME/.claude/CLAUDE.md"
    ln -sf "$REPO_ROOT/user-dev/preferences.md"        "$HOME/.claude/preferences.md"
    ln -sf "$REPO_ROOT/user-pers/user_tone_of_voice.md" "$HOME/.claude/user_tone_of_voice.md"
    ln -sf "$REPO_ROOT/user-pers/custom_instructions.md" "$HOME/.claude/custom_instructions.md"
    while IFS= read -r skill_dir; do
        ln -sfn "$skill_dir" "$HOME/.claude/skills/$(basename "$skill_dir")"
    done < <(list_skill_paths)
    # personal mobile layer — required by check-health.sh
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

@test "on-config-edit: silent exit when file is outside repo" {
    if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
    payload='{"tool_input":{"file_path":"/tmp/unrelated.md"}}'
    run bash -c "printf '%s' '$payload' | ./bin/on-config-edit.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "on-config-edit: silent exit when input is empty" {
    run bash -c "printf '' | ./bin/on-config-edit.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "on-config-edit: prints suggestions when editing a managed file" {
    if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
    payload="{\"tool_input\":{\"file_path\":\"$REPO_ROOT/user-dev/CLAUDE.md\"}}"
    run bash -c "printf '%s' '$payload' | ./bin/on-config-edit.sh"
    [ "$status" -eq 0 ]
    assert_contains "$output" "validation passed"
    assert_contains "$output" "agent-config-audit"
}
