#!/usr/bin/env bats
#
# Tests for bin/sync-back.sh — detection, no-op behavior, and the full
# branch/commit/push/PR flow. The flow tests run in consumer mode against a
# throwaway git repo with a local bare origin, and stub `gh`/`glab`/`claude`
# on PATH, so nothing touches this checkout or a real remote.

load helpers/common

setup() {
    cd "$REPO_ROOT"
    FIX=""
}

teardown() {
    if [ -n "${FIX:-}" ] && [ -d "$FIX" ]; then
        rm -rf "$FIX"
    fi
}

# Build: a consumer config repo ($CONSUMER, one registered domain `acme`)
# cloned from a local bare origin so push is real, a project dir ($PROJ) whose
# config drifted from the workspace copy, and a stub dir ($STUB) whose `gh` and
# `glab` record their argv instead of reaching a forge. Physical paths (pwd -P)
# because macOS mktemp hands out a symlinked /var path.
make_flow_fixture() {
    FIX=$(cd "$(mktemp -d)" && pwd -P)

    CONSUMER="$FIX/consumer"
    git init -q --bare "$FIX/origin.git"
    git clone -q "$FIX/origin.git" "$CONSUMER"
    git -C "$CONSUMER" config user.email test@example.com
    git -C "$CONSUMER" config user.name test
    mkdir -p "$CONSUMER/config" "$CONSUMER/workspace/acme"
    printf 'acme = workspace/acme : CLAUDE.md\n' > "$CONSUMER/config/domains.conf"
    printf '# Acme\n\n- Old rule.\n' > "$CONSUMER/workspace/acme/CLAUDE.md"
    git -C "$CONSUMER" add -A
    git -C "$CONSUMER" commit -qm init
    git -C "$CONSUMER" push -qu origin HEAD

    PROJ="$FIX/proj/acme"
    mkdir -p "$PROJ"
    printf '# Acme\n\n- New rule.\n' > "$PROJ/CLAUDE.md"

    STUB="$FIX/stub"
    mkdir -p "$STUB"
    printf '#!/bin/sh\necho "$*" >> "%s/gh.args"\n'   "$STUB" > "$STUB/gh"
    printf '#!/bin/sh\necho "$*" >> "%s/glab.args"\n' "$STUB" > "$STUB/glab"
    chmod +x "$STUB/gh" "$STUB/glab"
}

# A curated PATH for tests that need a tool ABSENT: `gh` is preinstalled on the
# CI runner and on developer machines, so no subtractive PATH can hide it.
# Symlink exactly the tools the script and lib/common.sh use into one dir.
make_toolbox() {
    TOOLBOX="$FIX/toolbox"
    mkdir -p "$TOOLBOX"
    local t
    for t in bash sh env dirname basename awk grep sed sort cut wc tr head \
             readlink cmp cp git date mktemp cat rm jq; do
        ln -s "$(command -v "$t")" "$TOOLBOX/$t"
    done
}

@test "sync-back: errors on missing project path" {
    run ./bin/sync-back.sh
    [ "$status" -ne 0 ]
    assert_contains "$output" "Usage"
}

@test "sync-back: errors on nonexistent path" {
    run ./bin/sync-back.sh "/no/such/path/exists/here-xyz"
    [ "$status" -ne 0 ]
    assert_contains "$output" "not found"
}

@test "sync-back: errors on unknown domain" {
    local fake_project
    fake_project=$(mktemp -d)
    mkdir -p "$fake_project/unrelated-domain-xyz"
    run ./bin/sync-back.sh "$fake_project/unrelated-domain-xyz"
    [ "$status" -ne 0 ]
    rm -rf "$fake_project"
}

@test "sync-back: wires a post-PR benchmark comment via gh and glab" {
    # Static check: the script must contain the PR-comment branch for both tools
    # and must honor AI_SETUP_SKIP_EVAL so CI runs don't hit the Claude CLI.
    grep -q 'gh pr comment'    ./bin/sync-back.sh
    grep -q 'glab mr note'     ./bin/sync-back.sh
    grep -q 'AI_SETUP_SKIP_EVAL' ./bin/sync-back.sh
}

@test "sync-back: no-op when files match" {
    # Set up a fake project that mirrors the workspace exactly.
    # mobile domain maps AGENTS.md (project) → project/CLAUDE.md (repo), so the
    # project must have AGENTS.md with the same content as repo's project/CLAUDE.md.
    local tmp fake_project
    tmp=$(mktemp -d)
    fake_project="$tmp/acme-mobile"
    mkdir -p "$fake_project"
    cp "$REPO_ROOT/workspace/mobile/project/CLAUDE.md" "$fake_project/AGENTS.md"
    cp "$REPO_ROOT/workspace/mobile/CLAUDE.md"      "$fake_project/CLAUDE.md"
    cp "$REPO_ROOT/workspace/mobile/.cursorrules"    "$fake_project/.cursorrules"

    run ./bin/sync-back.sh "$fake_project"
    [ "$status" -eq 0 ]
    assert_contains "$output" "Nothing to sync"
    rm -rf "$tmp"
}

@test "sync-back: syncs, branches, commits, pushes and opens the PR via gh" {
    make_flow_fixture
    run env PATH="$STUB:$PATH" AGENT_CONFIG_ROOT="$CONSUMER" AI_SETUP_SKIP_EVAL=1 \
        ./bin/sync-back.sh "$PROJ"
    [ "$status" -eq 0 ]
    assert_contains "$output" "synced: CLAUDE.md"

    # The drifted content was committed on a sync branch that reached the
    # origin. (The working tree is back on the original branch, so the file
    # there deliberately shows the pre-sync content.)
    local branch
    branch=$(git -C "$FIX/origin.git" for-each-ref --format='%(refname:short)' 'refs/heads/ai-config/sync-acme-*')
    [ -n "$branch" ]
    [ "$(git -C "$CONSUMER" show "$branch:workspace/acme/CLAUDE.md")" = "$(cat "$PROJ/CLAUDE.md")" ]

    # The PR went to the stub, against develop, and the checkout returned to
    # the original branch with eval explicitly skipped.
    assert_contains "$(cat "$STUB/gh.args")" "pr create --base develop --head $branch"
    assert_contains "$output" "Skipping benchmark comment"
    [ "$(git -C "$CONSUMER" branch --show-current)" != "$branch" ]
}

@test "sync-back: appends a counter when today's sync branch already exists" {
    make_flow_fixture
    git -C "$CONSUMER" branch "ai-config/sync-acme-$(date '+%Y-%m-%d')"
    run env PATH="$STUB:$PATH" AGENT_CONFIG_ROOT="$CONSUMER" AI_SETUP_SKIP_EVAL=1 \
        ./bin/sync-back.sh "$PROJ"
    [ "$status" -eq 0 ]
    # The pre-existing branch was left alone and the run coined a fresh name.
    [ "$(git -C "$CONSUMER" for-each-ref 'refs/heads/ai-config/*' | wc -l | tr -d ' ')" -eq 2 ]
    assert_contains "$output" "-2"
}

@test "sync-back: falls back to glab when gh is absent" {
    make_flow_fixture
    make_toolbox
    rm "$STUB/gh"
    run env PATH="$STUB:$TOOLBOX" AGENT_CONFIG_ROOT="$CONSUMER" AI_SETUP_SKIP_EVAL=1 \
        ./bin/sync-back.sh "$PROJ"
    [ "$status" -eq 0 ]
    assert_contains "$output" "Opening MR via glab"
    assert_contains "$(cat "$STUB/glab.args")" "mr create --target-branch develop"
}

@test "sync-back: says how to open the PR when no forge CLI exists" {
    make_flow_fixture
    make_toolbox
    rm "$STUB/gh" "$STUB/glab"
    run env PATH="$STUB:$TOOLBOX" AGENT_CONFIG_ROOT="$CONSUMER" AI_SETUP_SKIP_EVAL=1 \
        ./bin/sync-back.sh "$PROJ"
    [ "$status" -eq 0 ]
    assert_contains "$output" "Open the PR manually"
    assert_contains "$output" "Base: develop"
}

@test "sync-back: refreshes the benchmark and posts it as a PR comment" {
    make_flow_fixture
    # A stub `claude` turns the eval gate on and gives run-eval.sh a canned
    # score, so the comment path runs end to end without an API key.
    cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
cat <<'JSON'
{"date":"2026-01-01T00:00:00Z","domain":"acme","git_hash":"stub","scores":{"clarity":5,"conciseness":5,"completeness":5,"consistency":5,"actionability":5},"total":25,"percentage":100,"grade":"A","findings":[]}
JSON
EOF
    chmod +x "$STUB/claude"
    run env PATH="$STUB:$PATH" AGENT_CONFIG_ROOT="$CONSUMER" \
        ./bin/sync-back.sh "$PROJ"
    [ "$status" -eq 0 ]
    assert_contains "$output" "Re-scoring acme"
    # The comment carried the refreshed table to the PR through the stub.
    assert_contains "$(cat "$STUB/gh.args")" "pr comment"
    [ -n "$(find "$CONSUMER/benchmarks/scores" -name '*acme.json' 2>/dev/null)" ]
}

@test "sync-back: opens PRs against develop, not main" {
    # Pins the gitflow base. Without this, flipping the base back to main is
    # invisible to the suite — every other sync-back test is content-agnostic
    # about which branch the PR targets.
    grep -q 'gh pr create --base develop'          ./bin/sync-back.sh
    grep -q 'glab mr create --target-branch develop' ./bin/sync-back.sh
    ! grep -qE '(--base|--target-branch) main' ./bin/sync-back.sh
}
