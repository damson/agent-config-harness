#!/usr/bin/env bats
#
# Tests for bin/session-domains.sh: naming a project's domains by what it
# contains, wherever it sits. Runs against this repo's own example registry
# (config/domains.conf and config/domain-signals.conf).

load helpers/common

setup() {
    cd "$REPO_ROOT"
    setup_test_home
    PROJECTS="$(mktemp -d)"
}

teardown() {
    teardown_test_home
    [ -n "${PROJECTS:-}" ] && rm -rf "$PROJECTS"
}

# Run the hook for a session whose working directory is $1.
hook_in() {
    run bash -c "printf '{\"cwd\": \"%s\"}' '$1' | '$REPO_ROOT/bin/session-domains.sh'"
}

make_project() {
    local dir="$PROJECTS/$1"
    mkdir -p "$dir"
    ( cd "$dir" && git init -q . )
    printf '%s' "$dir"
}

@test "session-domains: an Android build names the mobile domain and its files" {
    p=$(make_project app)
    mkdir -p "$p/app"
    printf 'plugins { id("com.android.application") }\n' > "$p/app/build.gradle.kts"
    hook_in "$p"
    [ "$status" -eq 0 ]
    assert_contains "$output" "- mobile: $REPO_ROOT/workspace/mobile/CLAUDE.md"
}

@test "session-domains: a plugin applied through the version catalog still counts" {
    p=$(make_project catalog)
    mkdir -p "$p/gradle"
    printf 'plugins { alias(libs.plugins.android.application) }\n' > "$p/build.gradle.kts"
    hook_in "$p"
    assert_contains "$output" "- mobile:"
}

@test "session-domains: a repo spanning two stacks names both" {
    p=$(make_project fullstack)
    printf '{ "dependencies": { "next": "16.0.0", "react": "19.0.0", "fastify": "5.0.0" } }\n' > "$p/package.json"
    hook_in "$p"
    assert_contains "$output" "- web-react:"
    assert_contains "$output" "- backend-node:"
}

@test "session-domains: an exclusion keeps React Native out of web-react" {
    p=$(make_project rn)
    printf '{ "dependencies": { "react": "19.0.0", "react-native": "0.80.0" } }\n' > "$p/package.json"
    hook_in "$p"
    assert_contains "$output" "- mobile:"
    assert_not_contains "$output" "web-react"
}

@test "session-domains: a file under node_modules is not a signal" {
    p=$(make_project deps)
    mkdir -p "$p/node_modules/fastify"
    printf '{ "dependencies": { "fastify": "5.0.0" } }\n' > "$p/node_modules/fastify/package.json"
    hook_in "$p"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-domains: a project matching nothing prints nothing" {
    p=$(make_project plain)
    printf 'hello\n' > "$p/README.md"
    hook_in "$p"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-domains: a session already inside the domain's folder is not told again" {
    mkdir -p "$HOME/workspace/mobile/inside"
    p="$HOME/workspace/mobile/inside"
    ( cd "$p" && git init -q . )
    printf 'plugins { id("com.android.application") }\n' > "$p/build.gradle.kts"
    hook_in "$p"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-domains: a subfolder of the project is detected from the repository root" {
    p=$(make_project nested)
    mkdir -p "$p/src/deep"
    printf '{ "dependencies": { "express": "5.0.0" } }\n' > "$p/package.json"
    hook_in "$p/src/deep"
    assert_contains "$output" "- backend-node:"
}

@test "session-domains: an unreadable payload falls back to the working directory" {
    p=$(make_project garbled)
    printf '{ "dependencies": { "express": "5.0.0" } }\n' > "$p/package.json"
    run bash -c "cd '$p' && printf 'not json' | '$REPO_ROOT/bin/session-domains.sh'"
    [ "$status" -eq 0 ]
    assert_contains "$output" "- backend-node:"
}

@test "session-domains: a config repo with no signals file stays silent" {
    consumer="$(mktemp -d)"
    mkdir -p "$consumer/config"
    cp "$REPO_ROOT/config/domains.conf" "$consumer/config/"
    p=$(make_project nosignals)
    printf '{ "dependencies": { "express": "5.0.0" } }\n' > "$p/package.json"
    run bash -c "printf '{\"cwd\": \"%s\"}' '$p' | AGENT_CONFIG_ROOT='$consumer' '$REPO_ROOT/bin/session-domains.sh'"
    rm -rf "$consumer"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-domains: the config repo itself is no project, even when it looks like one" {
    consumer=$(make_project config-repo)
    mkdir -p "$consumer/config"
    cp "$REPO_ROOT/config/domains.conf" "$REPO_ROOT/config/domain-signals.conf" "$consumer/config/"
    printf '{ "dependencies": { "express": "5.0.0" } }\n' > "$consumer/package.json"
    run bash -c "printf '{\"cwd\": \"%s\"}' '$consumer' | AGENT_CONFIG_ROOT='$consumer' '$REPO_ROOT/bin/session-domains.sh'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
