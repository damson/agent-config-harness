#!/usr/bin/env bats
#
# Tests for the skill-marketplace registry, the structural validator, and
# bin/marketplaces.sh.
#
# Nothing here reaches the network: the registry cases read a throwaway conf,
# the validator cases build a throwaway skills tree rather than depending on the
# skills this repo happens to ship today, and the one case that would invoke the
# CLI runs with a PATH that has no `claude` on it.

load helpers/common

# A minimal well-formed skill. Callers mutate one thing to prove a check bites.
make_skill() {
    local root="$1" leaf="$2" name="${3:-$2}"
    mkdir -p "$root/$leaf"
    cat > "$root/$leaf/SKILL.md" <<EOF
---
name: $name
description: A description with actual content in it.
---

# $leaf

## Procedure

1. Do the thing.

## When to STOP

- When the thing is done.
EOF
}

setup() {
    cd "$REPO_ROOT"
    TREE=$(mktemp -d)
    CONF=$(mktemp)
    cat > "$CONF" <<'EOF'
# comment line, must be skipped
demo = owner/demo-repo :: alpha,beta :: https://example.invalid/demo
everything = owner/all-repo :: * :: https://example.invalid/all
EOF
    export MARKETPLACES_CONF="$CONF"
}

teardown() {
    rm -rf "$TREE"
    rm -f "$CONF"
}

# ── registry ──────────────────────────────────────────────

@test "marketplaces: list_marketplaces returns ids and skips comments" {
    run bash -c ". lib/common.sh; list_marketplaces | tr '\n' ' '"
    [ "$status" -eq 0 ]
    assert_contains "$output" "demo"
    assert_contains "$output" "everything"
    assert_not_contains "$output" "#"
}

@test "marketplaces: source, plugins and docs fields parse independently" {
    run bash -c ". lib/common.sh; get_marketplace_source demo"
    [ "$output" = "owner/demo-repo" ]
    run bash -c ". lib/common.sh; get_marketplace_plugins demo"
    [ "$output" = "alpha,beta" ]
    run bash -c ". lib/common.sh; get_marketplace_docs demo"
    [ "$output" = "https://example.invalid/demo" ]
}

@test "marketplaces: a wildcard plugin list is preserved verbatim" {
    run bash -c ". lib/common.sh; get_marketplace_plugins everything"
    [ "$output" = "*" ]
}

@test "marketplaces: marketplace_exists distinguishes registered from not" {
    run bash -c ". lib/common.sh; marketplace_exists demo"
    [ "$status" -eq 0 ]
    run bash -c ". lib/common.sh; marketplace_exists nope"
    [ "$status" -ne 0 ]
}

@test "marketplaces: install rejects an unregistered id instead of adding it" {
    # Deliberately run with a PATH that has no `claude` on it. The id is resolved
    # before the CLI is required, so a typo reports the typo rather than sending
    # you to install Claude Code — and this test then means the same thing on a
    # developer machine and in CI, where the CLI is absent.
    run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" ./bin/marketplaces.sh install not-registered
    [ "$status" -ne 0 ]
    assert_contains "$output" "Unknown marketplace"
    assert_not_contains "$output" "not on PATH"
}

# ── validator ─────────────────────────────────────────────

@test "validate-skills: a well-formed tree passes" {
    make_skill "$TREE" good-skill
    run ./bin/validate-skills.sh "$TREE"
    [ "$status" -eq 0 ]
    assert_contains "$output" "pass all structural checks"
}

@test "validate-skills: frontmatter name must match the folder name" {
    make_skill "$TREE" good-skill
    make_skill "$TREE" mismatched some-other-name
    run ./bin/validate-skills.sh "$TREE"
    [ "$status" -ne 0 ]
    assert_contains "$output" "must match the folder name"
}

@test "validate-skills: a missing When to STOP section fails" {
    make_skill "$TREE" good-skill
    mkdir -p "$TREE/nostop"
    printf -- '---\nname: nostop\ndescription: x\n---\n\n## Procedure\n\n1. y\n' \
        > "$TREE/nostop/SKILL.md"
    run ./bin/validate-skills.sh "$TREE"
    [ "$status" -ne 0 ]
    assert_contains "$output" "When to STOP"
}

@test "validate-skills: a missing Procedure section fails" {
    make_skill "$TREE" good-skill
    mkdir -p "$TREE/noproc"
    printf -- '---\nname: noproc\ndescription: x\n---\n\n## When to STOP\n\n- z\n' \
        > "$TREE/noproc/SKILL.md"
    run ./bin/validate-skills.sh "$TREE"
    [ "$status" -ne 0 ]
    assert_contains "$output" "Procedure"
}

@test "validate-skills: an empty description fails" {
    make_skill "$TREE" good-skill
    mkdir -p "$TREE/nodesc"
    printf -- '---\nname: nodesc\ndescription:\n---\n\n## Procedure\n\n1. y\n\n## When to STOP\n\n- z\n' \
        > "$TREE/nodesc/SKILL.md"
    run ./bin/validate-skills.sh "$TREE"
    [ "$status" -ne 0 ]
    assert_contains "$output" "description"
}

@test "validate-skills: a folded description block counts as non-empty" {
    mkdir -p "$TREE/folded"
    printf -- '---\nname: folded\ndescription: >\n  Real content, wrapped onto\n  a second line.\n---\n\n## Procedure\n\n1. y\n\n## When to STOP\n\n- z\n' \
        > "$TREE/folded/SKILL.md"
    run ./bin/validate-skills.sh "$TREE"
    [ "$status" -eq 0 ]
}

@test "validate-skills: a duplicate leaf name across a group fails" {
    # Skills install FLAT, so two dirs with the same leaf shadow each other.
    make_skill "$TREE" collide
    mkdir -p "$TREE/group"
    make_skill "$TREE/group" collide
    run ./bin/validate-skills.sh "$TREE"
    [ "$status" -ne 0 ]
    assert_contains "$output" "duplicate leaf name"
}

@test "validate-skills: reports every problem, not just the first" {
    mkdir -p "$TREE/a" "$TREE/b"
    printf -- '---\nname: a\ndescription: x\n---\n\n## Procedure\n\n1. y\n' > "$TREE/a/SKILL.md"
    printf -- '---\nname: b\ndescription: x\n---\n\n## Procedure\n\n1. y\n' > "$TREE/b/SKILL.md"
    run ./bin/validate-skills.sh "$TREE"
    [ "$status" -ne 0 ]
    # A validator that stops at the first failure makes you run it once per problem.
    assert_contains "$output" "2 problem(s)"
}

@test "validate-skills: an unknown marketplace fails rather than passing vacuously" {
    run ./bin/validate-skills.sh --marketplace definitely-not-installed
    [ "$status" -ne 0 ]
    assert_contains "$output" "no installed plugins"
}

@test "validate-skills: a directory with no skills fails rather than reporting success" {
    run ./bin/validate-skills.sh "$TREE"
    [ "$status" -ne 0 ]
    assert_contains "$output" "No skills found"
}
