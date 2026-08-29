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
