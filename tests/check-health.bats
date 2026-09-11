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

@test "check-health: a real file where a link belongs is a failure, not a note" {
    # setup.sh backs such a file up and replaces it with the link, so finding
    # one means setup has not run since it appeared and none of this repo's
    # config is in effect. Counting it as a warning only let the run print the
    # warning and "All systems nominal" together, and exit 0.
    rm "$HOME/.claude/CLAUDE.md"
    printf '# not the managed file\n' > "$HOME/.claude/CLAUDE.md"
    run ./bin/check-health.sh
    [ "$status" -ne 0 ]
    assert_contains "$output" "exists but is not a symlink"
    assert_not_contains "$output" "All systems nominal"
}

@test "check-health: an external provider that IS installed is reported as such" {
    # Every other external-skills test runs with none installed, so the
    # installed branch had never executed.
    . lib/common.sh
    local first probe
    first=$(list_external_skills | head -1)
    [ -n "$first" ]
    probe=$(get_external_probe "$first")
    mkdir -p "$probe"
    run ./bin/check-health.sh
    assert_contains "$output" "external skill: $first"
    assert_not_contains "$output" "external skill: $first not installed"
}

# --- A consumer repo whose tree does not match its registry ------------------
# The registry is edited by hand, so it outruns the tree: a domain added before
# its folder, a file renamed in the workspace and not in the registry. Both are
# what check-health exists to catch, and neither had a test.

make_consumer() {
    CONSUMER=$(mktemp -d)
    mkdir -p "$CONSUMER/config"
    printf 'acme = workspace/acme : CLAUDE.md\n' > "$CONSUMER/config/domains.conf"
}

@test "check-health: a registered domain with no workspace folder fails the run" {
    make_consumer
    run env AGENT_CONFIG_ROOT="$CONSUMER" ./bin/check-health.sh
    rm -rf "$CONSUMER"
    [ "$status" -ne 0 ]
    assert_contains "$output" "domain 'acme' workspace MISSING"
    # It moves on to the next domain rather than looking for files inside a
    # folder that is not there.
    assert_not_contains "$output" "acme/CLAUDE.md: MISSING"
}

@test "check-health: a managed file the workspace does not have fails the run" {
    make_consumer
    mkdir -p "$CONSUMER/workspace/acme"
    run env AGENT_CONFIG_ROOT="$CONSUMER" ./bin/check-health.sh
    rm -rf "$CONSUMER"
    [ "$status" -ne 0 ]
    assert_contains "$output" "acme/CLAUDE.md: MISSING"
}

@test "check-health: a repo with no skills directory says so instead of passing quietly" {
    make_consumer
    mkdir -p "$CONSUMER/workspace/acme"
    printf '# Acme\n' > "$CONSUMER/workspace/acme/CLAUDE.md"
    run env AGENT_CONFIG_ROOT="$CONSUMER" ./bin/check-health.sh
    rm -rf "$CONSUMER"
    assert_contains "$output" "skills directory missing"
}
