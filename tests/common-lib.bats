#!/usr/bin/env bats
#
# Tests for lib/common.sh — registry reader and helpers.

load helpers/common

setup() {
    cd "$REPO_ROOT"
    # shellcheck disable=SC1091
    . lib/common.sh
}

@test "list_domains: returns all registered domains" {
    run list_domains
    [ "$status" -eq 0 ]
    assert_contains "$output" "mobile"
    assert_contains "$output" "web-react"
    assert_contains "$output" "backend-node"
    assert_contains "$output" "data-extraction"
}

@test "get_domain_workspace: mobile → workspace/mobile" {
    run get_domain_workspace "mobile"
    [ "$status" -eq 0 ]
    [ "$output" = "workspace/mobile" ]
}

@test "get_domain_workspace: unknown domain → empty" {
    run get_domain_workspace "no-such-domain"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "get_domain_files: mobile emits repo-side dest paths (project/CLAUDE.md, not AGENTS.md)" {
    run get_domain_files "mobile"
    [ "$status" -eq 0 ]
    assert_contains "$output" "project/CLAUDE.md"
    assert_contains "$output" "CLAUDE.md"
    assert_contains "$output" ".cursorrules"
    assert_not_contains "$output" "AGENTS.md"
}

@test "get_domain_file_src: mobile AGENTS.md>project/CLAUDE.md mapping resolves correctly" {
    run get_domain_file_src "mobile" "project/CLAUDE.md"
    [ "$status" -eq 0 ]
    [ "$output" = "AGENTS.md" ]
}

@test "get_domain_file_src: unmapped file returns itself" {
    run get_domain_file_src "mobile" "CLAUDE.md"
    [ "$status" -eq 0 ]
    [ "$output" = "CLAUDE.md" ]
}

@test "get_domain_files: data-extraction is CLAUDE.md only (AGENTS.md is a symlink, no .cursorrules)" {
    run get_domain_files "data-extraction"
    [ "$status" -eq 0 ]
    assert_contains "$output" "CLAUDE.md"
    assert_not_contains "$output" "AGENTS.md"
    assert_not_contains "$output" ".cursorrules"
}

@test "domains: AGENTS.md is a symlink to CLAUDE.md in each non-mobile workspace" {
    for d in web-react backend-node data-extraction; do
        [ -L "$REPO_ROOT/workspace/$d/AGENTS.md" ] || { echo "workspace/$d/AGENTS.md is not a symlink"; return 1; }
        [ "$(readlink "$REPO_ROOT/workspace/$d/AGENTS.md")" = "CLAUDE.md" ] || { echo "workspace/$d/AGENTS.md does not point to CLAUDE.md"; return 1; }
        # symlink resolves to real content
        [ -f "$REPO_ROOT/workspace/$d/AGENTS.md" ] || { echo "workspace/$d/AGENTS.md does not resolve"; return 1; }
    done
}

@test "domains: duplicate .cursorrules are symlinks to CLAUDE.md; mobile's is a real file" {
    for d in web-react backend-node; do
        [ -L "$REPO_ROOT/workspace/$d/.cursorrules" ] || { echo "workspace/$d/.cursorrules is not a symlink"; return 1; }
        [ "$(readlink "$REPO_ROOT/workspace/$d/.cursorrules")" = "CLAUDE.md" ] || { echo "workspace/$d/.cursorrules does not point to CLAUDE.md"; return 1; }
    done
    # mobile's .cursorrules carries unique content — it must stay a real file
    [ ! -L "$REPO_ROOT/workspace/mobile/.cursorrules" ] || { echo "mobile/.cursorrules should be a real file, not a symlink"; return 1; }
}

@test "domain_exists: returns 0 for mobile" {
    run domain_exists "mobile"
    [ "$status" -eq 0 ]
}

@test "domain_exists: returns non-zero for missing domain" {
    run domain_exists "xyz-nope"
    [ "$status" -ne 0 ]
}

@test "get_domain_workspaces: web-react lists canonical path then alias" {
    run get_domain_workspaces "web-react"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "workspace/web-react" ]
    [ "${lines[1]}" = "workspace/web" ]
}

@test "get_domain_workspace: returns only the canonical path, never an alias" {
    # Callers read, write and score files here — an alias holds no config.
    run get_domain_workspace "web-react"
    [ "$status" -eq 0 ]
    [ "$output" = "workspace/web-react" ]
}

@test "list_external_skills: returns all registered providers" {
    run list_external_skills
    [ "$status" -eq 0 ]
    assert_contains "$output" "android-skills"
    assert_contains "$output" "impeccable"
}

@test "get_external_install: android-skills → the vendor CLI command" {
    run get_external_install "android-skills"
    [ "$status" -eq 0 ]
    [ "$output" = "android skills add --all" ]
}

@test "external_skill_exists: returns non-zero for an unregistered id" {
    run external_skill_exists "xyz-nope"
    [ "$status" -ne 0 ]
}

@test "detect_domain: a docs/ component does not make a project path ambiguous" {
    # Registering the repo's own docs for scoring must not cost us detection:
    # detect_domain matches a domain name as a substring of any path component,
    # so a domain literally named "docs" would collide with every project that
    # has a docs/ directory.
    run detect_domain "/Users/x/workspace/web-react/my-app/docs"
    [ "$status" -eq 0 ]
    [ "$output" = "web-react" ]
}

@test "detect_domain: a canonical workspace leaf is not an alias" {
    # Only EXTRA registry paths become aliases. If the canonical leaf did too, a
    # domain rooted at a common word — repo-docs lives at docs/ — would match
    # every project holding a directory of that name and force a false ambiguity.
    run detect_domain "/Users/x/workspace/web-react/my-app/docs"
    [ "$status" -eq 0 ]
    [ "$output" = "web-react" ]

    # The extra path still resolves, which is the point of the feature.
    run detect_domain "/Users/x/workspace/web/my-app"
    [ "$status" -eq 0 ]
    [ "$output" = "web-react" ]
}

# --- extract_json_object -----------------------------------------------------
# The eval runners feed a model's reply through this. Every case below was seen
# in a real reply; the fenced one silently discarded every skill score (#51).

@test "extract_json_object: unwraps a \`\`\`json fenced block" {
    run bash -c 'printf "%s\n" '"'"'```json'"'"' "{" "  \"total\": 22" "}" '"'"'```'"'"' | { . lib/common.sh; extract_json_object; } | jq -r .total'
    [ "$status" -eq 0 ]
    [ "$output" = "22" ]
}

@test "extract_json_object: takes a bare object with no fence" {
    run bash -c 'printf "%s\n" "{" "  \"total\": 7" "}" | { . lib/common.sh; extract_json_object; } | jq -r .total'
    [ "$status" -eq 0 ]
    [ "$output" = "7" ]
}

@test "extract_json_object: ignores prose before and after" {
    run bash -c 'printf "%s\n" "Here is the evaluation:" "{" "  \"total\": 19" "}" "Let me know if you want more detail." | { . lib/common.sh; extract_json_object; } | jq -r .total'
    [ "$status" -eq 0 ]
    [ "$output" = "19" ]
}

@test "extract_json_object: handles a single-line object" {
    run bash -c 'printf "%s\n" "{\"total\": 25}" | { . lib/common.sh; extract_json_object; } | jq -r .total'
    [ "$status" -eq 0 ]
    [ "$output" = "25" ]
}

@test "extract_json_object: fails when the reply holds no object" {
    run bash -c 'printf "%s\n" "I could not evaluate that." | { . lib/common.sh; extract_json_object; }'
    [ "$status" -ne 0 ]
}

@test "require: a missing tool fails with the install hint when given one" {
    run bash -c ". lib/common.sh; require definitely-not-a-real-tool 'brew install nothing'"
    [ "$status" -ne 0 ]
    assert_contains "$output" "definitely-not-a-real-tool"
    assert_contains "$output" "brew install nothing"
}

@test "require: a missing tool without a hint still names the tool" {
    # The hintless branch is the one every caller that omits the second
    # argument takes, and it must not print an empty "Install:" tail.
    run bash -c ". lib/common.sh; require definitely-not-a-real-tool"
    [ "$status" -ne 0 ]
    assert_contains "$output" "not found in PATH"
    assert_not_contains "$output" "Install:"
}

@test "require: a present tool is silent and does not exit" {
    run bash -c ". lib/common.sh; require sh; echo reached-the-end"
    [ "$status" -eq 0 ]
    assert_contains "$output" "reached-the-end"
}

# --- A missing registry ------------------------------------------------------
# Every reader below is "guard | awk", and a pipeline reports awk's status. The
# guard printed its error from inside the left-hand subshell and the call still
# exited 0 with no output, so a caller looping over the result did nothing and
# said nothing about it.

@test "list_domains: a missing registry fails instead of reporting no domains" {
    run bash -c ". lib/common.sh; DOMAINS_CONF=/nonexistent/domains.conf; list_domains"
    [ "$status" -ne 0 ]
    assert_contains "$output" "Domain registry not found"
}

@test "get_domain_workspaces: a missing registry fails instead of returning empty" {
    # A second entry point, because the guard has to sit in each of them: they
    # reach the registry directly, not through list_domains.
    run bash -c ". lib/common.sh; DOMAINS_CONF=/nonexistent/domains.conf; get_domain_workspaces mobile"
    [ "$status" -ne 0 ]
    assert_contains "$output" "Domain registry not found"
}

@test "list_external_skills: a missing registry fails instead of reporting no providers" {
    run bash -c ". lib/common.sh; EXTERNAL_SKILLS_CONF=/nonexistent/external.conf; list_external_skills"
    [ "$status" -ne 0 ]
    assert_contains "$output" "External skill registry not found"
}

@test "get_external_install: a missing registry fails instead of returning empty" {
    run bash -c ". lib/common.sh; EXTERNAL_SKILLS_CONF=/nonexistent/external.conf; get_external_install android-skills"
    [ "$status" -ne 0 ]
    assert_contains "$output" "External skill registry not found"
}

@test "get_domain_workspace: a missing registry fails rather than reporting no workspace" {
    # This one wraps its own pipe: get_domain_workspaces | head -1. The guard
    # fires inside the left-hand subshell, and head returns 0 on empty input,
    # so the wrapper needs the guard in its own shell too.
    run bash -c ". lib/common.sh; DOMAINS_CONF=/nonexistent/domains.conf; get_domain_workspace mobile"
    [ "$status" -ne 0 ]
    assert_contains "$output" "Domain registry not found"
}

@test "domain_exists: a missing registry fails rather than answering no" {
    # The wrong answer is worse than the empty one: grep finds nothing and the
    # caller is told the domain does not exist, which is not what was measured.
    run bash -c ". lib/common.sh; DOMAINS_CONF=/nonexistent/domains.conf; domain_exists mobile"
    [ "$status" -ne 0 ]
    assert_contains "$output" "Domain registry not found"
}

@test "external_skill_exists: a missing registry fails rather than answering no" {
    run bash -c ". lib/common.sh; EXTERNAL_SKILLS_CONF=/nonexistent/external.conf; external_skill_exists impeccable"
    [ "$status" -ne 0 ]
    assert_contains "$output" "External skill registry not found"
}

@test "the wrappers still answer correctly when the registry is there" {
    # Control for the three above: a guard that rejected everything would make
    # them pass and the library useless.
    run bash -c ". lib/common.sh; get_domain_workspace mobile; domain_exists mobile && external_skill_exists impeccable && echo both-found"
    [ "$status" -eq 0 ]
    assert_contains "$output" "workspace/mobile"
    assert_contains "$output" "both-found"
}

@test "domains: a present registry still reads cleanly after the guard" {
    # The control: a guard that rejected everything would make the four tests
    # above pass and the reader useless.
    run list_domains
    [ "$status" -eq 0 ]
    assert_contains "$output" "mobile"
}

# --- External registry fields ------------------------------------------------
# Only field 3 had a test. An off-by-one inside _external_field would leave that
# one passing while every other accessor returned a neighbouring column.

@test "get_external_requires: android-skills names the command that must be on PATH" {
    run get_external_requires "android-skills"
    [ "$status" -eq 0 ]
    [ "$output" = "android" ]
}

@test "get_external_docs: android-skills returns the documentation URL" {
    run get_external_docs "android-skills"
    [ "$status" -eq 0 ]
    [ "$output" = "https://developer.android.com/studio/cli" ]
}

@test "get_external_probe: a leading ~ expands to \$HOME" {
    # The probe is the only field transformed rather than returned verbatim, and
    # an unexpanded ~ names a path that never exists: the installer would then
    # reinstall a bundle that is already there on every run.
    run bash -c 'HOME=/tmp/ai-setup-probe-home; . lib/common.sh; get_external_probe android-skills'
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/ai-setup-probe-home/.claude/skills/android-cli" ]
}

@test "external fields: a line shorter than the field asked for yields nothing" {
    local conf
    conf=$(mktemp)
    printf 'short = tool :: ~/probe\n' > "$conf"
    run bash -c ". lib/common.sh; EXTERNAL_SKILLS_CONF='$conf'; get_external_docs short"
    rm -f "$conf"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- list_skill_dirs ---------------------------------------------------------
# Nothing exercised this. tests/skills.bats walks the tree with its own find and
# the helper that does it says to keep the two in step; the last test here is
# what makes that true rather than hoped for.

@test "list_skill_dirs: finds a top-level skill and descends into a group" {
    local root expected
    root=$(mktemp -d)
    mkdir -p "$root/solo" "$root/group/first" "$root/group/second" "$root/not-a-skill"
    touch "$root/solo/SKILL.md" "$root/group/first/SKILL.md" "$root/group/second/SKILL.md"
    run bash -c ". lib/common.sh; SKILLS_DIR='$root'; list_skill_dirs | sort"
    # Exact list: the group container holds no SKILL.md and is a container, and
    # a directory holding neither is neither.
    expected=$(printf '%s\n' "$root/group/first" "$root/group/second" "$root/solo")
    rm -rf "$root"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test "list_skill_dirs: a root that does not exist is silence, not an error" {
    run bash -c ". lib/common.sh; SKILLS_DIR=/nonexistent/skills; list_skill_dirs"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "list_skill_dirs: agrees with the find the test helper walks the tree with" {
    run bash -c ". lib/common.sh; list_skill_dirs | sort"
    [ "$status" -eq 0 ]
    [ "$output" = "$(list_skill_paths)" ]
}

# --- The two roots -----------------------------------------------------------
# HARNESS_ROOT is this checkout; REPO_ROOT is the config repo being managed.
# Getting them backwards is silent: the engine reads its own example domains and
# reports healthy.

@test "AGENT_CONFIG_ROOT: a path that is not a directory refuses to load" {
    run bash -c "AGENT_CONFIG_ROOT='$REPO_ROOT/README.md' . lib/common.sh"
    [ "$status" -ne 0 ]
    assert_contains "$output" "AGENT_CONFIG_ROOT is not a directory"
}

@test "AGENT_CONFIG_ROOT: REPO_ROOT follows it while HARNESS_ROOT stays this checkout" {
    local elsewhere
    elsewhere=$(mktemp -d)
    run bash -c "AGENT_CONFIG_ROOT='$elsewhere' . lib/common.sh; printf '%s\n%s\n' \"\$REPO_ROOT\" \"\$HARNESS_ROOT\""
    rm -rf "$elsewhere"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | head -1)" = "$elsewhere" ]
    [ "$(printf '%s\n' "$output" | tail -1)" = "$REPO_ROOT" ]
}
