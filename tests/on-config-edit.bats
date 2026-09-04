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

@test "on-config-edit: an in-repo file that is not managed exits silently" {
    if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
    # README.md lives in the repo but is not a config file, so the hook must
    # not spend a health check and a lint on it.
    payload="{\"tool_input\":{\"file_path\":\"$REPO_ROOT/README.md\"}}"
    run bash -c "printf '%s' '$payload' | ./bin/on-config-edit.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "on-config-edit: a failing health check blocks with the failure" {
    if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
    # The hook's whole point is stopping Claude when a config edit broke
    # something. Break one global link the fixture just made.
    rm "$HOME/.claude/preferences.md"
    payload="{\"tool_input\":{\"file_path\":\"$REPO_ROOT/user-dev/CLAUDE.md\"}}"
    run bash -c "printf '%s' '$payload' | ./bin/on-config-edit.sh"
    [ "$status" -eq 1 ]
    assert_contains "$output" "Health check failed"
    # The child's own diagnosis is passed through, not swallowed.
    assert_contains "$output" "preferences.md"
    assert_not_contains "$output" "validation passed"
}

@test "on-config-edit: a failing secret lint blocks with the failure" {
    if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
    # Consumer mode against a local clone, so the planted secret is tracked
    # somewhere real without touching this checkout. The clone carries the
    # same domains and workspace files, so the health check still passes and
    # the lint branch is the one under test.
    local clone="$TEST_HOME/clone"
    git clone -q --local "$REPO_ROOT" "$clone"
    # Assembled from parts: written literally, this line would be a tracked
    # secret in THIS repo and would fail the real `just lint`.
    local key="api" val="Qw8rTy2uIo5pAs1d"
    printf '%s_key = "%s"\n' "$key" "$val" > "$clone/planted.env"
    git -C "$clone" add planted.env
    git -C "$clone" -c user.email=t@example.com -c user.name=t commit -qm "plant"

    payload="{\"tool_input\":{\"file_path\":\"$clone/user-dev/CLAUDE.md\"}}"
    run bash -c "printf '%s' '$payload' | AGENT_CONFIG_ROOT='$clone' ./bin/on-config-edit.sh"
    [ "$status" -eq 1 ]
    assert_contains "$output" "Secret lint failed"
    assert_contains "$output" "planted.env"
}

@test "on-config-edit: exits silently when jq is unavailable" {
    # jq parses the hook's stdin. Without it the hook cannot tell a config
    # edit from any other, and must get out of the way rather than guess.
    local tb="$TEST_HOME/toolbox"
    mkdir -p "$tb"
    local t
    for t in bash cat dirname basename printf; do
        [ -e "$(command -v "$t")" ] && ln -sf "$(command -v "$t")" "$tb/$t"
    done
    payload="{\"tool_input\":{\"file_path\":\"$REPO_ROOT/user-dev/CLAUDE.md\"}}"
    run env PATH="$tb" bash -c "printf '%s' '$payload' | ./bin/on-config-edit.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
