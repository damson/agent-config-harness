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

@test "session-domains: a monorepo's package is found two folders down" {
    p=$(make_project mono)
    mkdir -p "$p/apps/web"
    printf '{ "workspaces": ["apps/*"] }\n' > "$p/package.json"
    printf '{ "dependencies": { "next": "16.0.0" } }\n' > "$p/apps/web/package.json"
    hook_in "$p"
    assert_contains "$output" "- web-react:"
}

@test "session-domains: a monorepo with a web app and a React Native app names both" {
    p=$(make_project both)
    mkdir -p "$p/apps/web" "$p/apps/mobile"
    printf '{ "dependencies": { "next": "16.0.0", "react": "19.0.0" } }\n' > "$p/apps/web/package.json"
    printf '{ "dependencies": { "react": "19.0.0", "expo": "54.0.0" } }\n' > "$p/apps/mobile/package.json"
    hook_in "$p"
    assert_contains "$output" "- web-react:"
    assert_contains "$output" "- mobile:"
}

@test "session-domains: a file under node_modules is not a signal" {
    p=$(make_project deps)
    # within the search depth, so only the node_modules exclusion keeps it out
    mkdir -p "$p/node_modules"
    printf '{ "dependencies": { "fastify": "5.0.0" } }\n' > "$p/node_modules/package.json"
    hook_in "$p"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-domains: the right file name with none of the domain's content is no match" {
    p=$(make_project lodash)
    printf '{ "dependencies": { "lodash": "4.17.21" } }\n' > "$p/package.json"
    hook_in "$p"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-domains: a dot in a glob matches only a dot" {
    p=$(make_project lookalike)
    printf 'plugins { id("com.android.application") }\n' > "$p/buildXgradle.kts"
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
    printf '# mobile\n' > "$HOME/workspace/mobile/CLAUDE.md"
    p="$HOME/workspace/mobile/inside"
    ( cd "$p" && git init -q . )
    printf 'plugins { id("com.android.application") }\n' > "$p/build.gradle.kts"
    hook_in "$p"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-domains: a folder that does not load the domain yet is no reason to stay quiet" {
    # an alias folder full of projects, before setup has linked a CLAUDE.md into it
    mkdir -p "$HOME/workspace/web/site"
    p="$HOME/workspace/web/site"
    ( cd "$p" && git init -q . )
    printf '{ "dependencies": { "react": "19.0.0" } }\n' > "$p/package.json"
    hook_in "$p"
    assert_contains "$output" "- web-react:"
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
    # a domain file to name, so only the config-repo check keeps it quiet
    mkdir -p "$consumer/workspace/backend-node"
    printf '# backend\n' > "$consumer/workspace/backend-node/CLAUDE.md"
    printf '{ "dependencies": { "express": "5.0.0" } }\n' > "$consumer/package.json"
    run bash -c "printf '{\"cwd\": \"%s\"}' '$consumer' | AGENT_CONFIG_ROOT='$consumer' '$REPO_ROOT/bin/session-domains.sh'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-domains: a web project's browser-test dependency is not a data-extraction signal" {
    p=$(make_project webe2e)
    printf '{ "dependencies": { "next": "16.0.0", "react": "19.0.0" } }\n' > "$p/package.json"
    printf '[project]\nname = "web"\n[dependency-groups]\ndev = ["pytest", "pytest-playwright>=0.5"]\n' > "$p/pyproject.toml"
    hook_in "$p"
    [ "$status" -eq 0 ]
    assert_contains "$output" "- web-react:"
    assert_not_contains "$output" "- data-extraction:"
}

@test "session-domains: a pyproject naming any one of the dependencies counts" {
    # One project per name, each listing only that one: a fixture carrying two
    # of them passes while either is still in the pattern, which is how the
    # first version of this test survived having a name taken out.
    for dep in scrapy playwright apache-airflow dagster prefect; do
        p=$(make_project "uses-$dep")
        printf '[project]\nname = "x"\ndependencies = ["%s>=1"]\n' "$dep" > "$p/pyproject.toml"
        hook_in "$p"
        assert_contains "$output" "- data-extraction:"
    done
}

@test "session-domains: a signal three folders down is out of the search" {
    p=$(make_project deeper)
    mkdir -p "$p/apps/web/sub"
    printf '{ "dependencies": { "next": "16.0.0" } }\n' > "$p/apps/web/sub/package.json"
    hook_in "$p"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-domains: a build output directory is pruned like node_modules" {
    p=$(make_project built)
    mkdir -p "$p/build"
    printf '{ "dependencies": { "fastify": "5.0.0" } }\n' > "$p/build/package.json"
    hook_in "$p"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-domains: a requirements file names the domain only on the dependency itself" {
    p=$(make_project reqs)
    printf 'scrapy==2.11\n' > "$p/requirements.txt"
    hook_in "$p"
    assert_contains "$output" "- data-extraction:"

    q=$(make_project reqs-e2e)
    printf 'pytest-playwright==0.5\n' > "$q/requirements.txt"
    hook_in "$q"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-domains: a config repo with no domain registry stays silent" {
    consumer="$(mktemp -d)"
    mkdir -p "$consumer/config"
    cp "$REPO_ROOT/config/domain-signals.conf" "$consumer/config/"
    p=$(make_project noregistry)
    printf '{ "dependencies": { "express": "5.0.0" } }\n' > "$p/package.json"
    run bash -c "printf '{\"cwd\": \"%s\"}' '$p' | AGENT_CONFIG_ROOT='$consumer' '$REPO_ROOT/bin/session-domains.sh'"
    rm -rf "$consumer"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
