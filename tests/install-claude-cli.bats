#!/usr/bin/env bats
#
# Tests for bin/install-claude-cli.sh — the action's CLI install step.
#
# The guarantee under test is SECURITY.md's: the job never runs a Claude CLI
# other than the pinned one. Every case runs against a curated PATH holding
# stub `claude`, `npm` and `jq`, so nothing installs anything for real.

load helpers/common

SCRIPT="$REPO_ROOT/bin/install-claude-cli.sh"

setup() {
    cd "$REPO_ROOT"
    BIN=$(mktemp -d)
    # The whole PATH, curated: the few tools the script and the stubs use,
    # symlinked in. A subtractive PATH cannot work here — the jq-missing case
    # needs jq genuinely absent, and on a GitHub runner jq lives in /usr/bin
    # alongside everything else.
    local t
    # bash too: `env` resolves the interpreter through this PATH as well.
    for t in bash grep head sed chmod; do ln -s "$(command -v "$t")" "$BIN/$t"; done
    # jq is required up front; the real one is fine, it is only probed.
    ln -s "$(command -v jq)" "$BIN/jq"
}

teardown() {
    rm -rf "$BIN"
}

# A stub `claude` reporting $1 as its version, in the real CLI's format.
# Called with no argument, it reports nothing parseable.
stub_claude() {
    if [ $# -eq 0 ]; then
        printf '#!/bin/sh\necho "unknown"\n' > "$BIN/claude"
    else
        printf '#!/bin/sh\necho "%s (Claude Code)"\n' "$1" > "$BIN/claude"
    fi
    chmod +x "$BIN/claude"
}

# A stub `npm` that records its argv and rewrites `claude` to report the
# version it was asked to install — what a working install looks like.
stub_npm() {
    cat > "$BIN/npm" <<EOF
#!/bin/sh
echo "\$@" >> "$BIN/npm.args"
v=\$(printf '%s' "\$3" | sed 's/.*@//')
printf '#!/bin/sh\necho "%s (Claude Code)"\n' "\$v" > "$BIN/claude"
chmod +x "$BIN/claude"
EOF
    chmod +x "$BIN/npm"
}

run_install() {
    run env PATH="$BIN" CLAUDE_VERSION="${1-}" bash "$SCRIPT"
}

@test "install-claude-cli: a non-exact version is refused before anything installs" {
    stub_npm
    run_install "latest"
    [ "$status" -ne 0 ]
    assert_contains "$output" "must be an exact x.y.z version"
    [ ! -e "$BIN/npm.args" ]
}

@test "install-claude-cli: an empty version is refused" {
    stub_npm
    run_install ""
    [ "$status" -ne 0 ]
    assert_contains "$output" "must be an exact x.y.z version"
}

@test "install-claude-cli: a bare major.minor is refused" {
    stub_npm
    run_install "2.1"
    [ "$status" -ne 0 ]
    assert_contains "$output" "must be an exact x.y.z version"
}

@test "install-claude-cli: a bad version is refused even when a CLI is present" {
    # The old step validated the pin only on the branch that installed, so a
    # malformed claude-version was accepted outright on a runner that already
    # had a CLI.
    stub_claude "2.1.259"
    stub_npm
    run_install "latest"
    [ "$status" -ne 0 ]
    assert_contains "$output" "must be an exact x.y.z version"
}

@test "install-claude-cli: no CLI present installs the pin" {
    stub_npm
    run_install "2.1.259"
    [ "$status" -eq 0 ]
    assert_contains "$(cat "$BIN/npm.args")" "@anthropic-ai/claude-code@2.1.259"
    assert_contains "$output" "Claude CLI 2.1.259 installed"
}

@test "install-claude-cli: a pre-installed CLI at the pin is used as is" {
    stub_claude "2.1.259"
    stub_npm
    run_install "2.1.259"
    [ "$status" -eq 0 ]
    assert_contains "$output" "matches the requested pin"
    # The fast path must not install: that is the whole point of taking it.
    [ ! -e "$BIN/npm.args" ]
}

@test "install-claude-cli: a pre-installed CLI at the WRONG version is installed over" {
    # The bug this guards: the old step skipped installation whenever any
    # claude was on PATH, so the pin was silently ignored and the API key went
    # to a version the action never chose.
    stub_claude "1.0.0"
    stub_npm
    run_install "2.1.259"
    [ "$status" -eq 0 ]
    assert_contains "$output" "not the requested 2.1.259"
    assert_contains "$(cat "$BIN/npm.args")" "@anthropic-ai/claude-code@2.1.259"
    assert_contains "$output" "Claude CLI 2.1.259 installed"
}

@test "install-claude-cli: a CLI with an unreadable version is installed over" {
    stub_claude
    stub_npm
    run_install "2.1.259"
    [ "$status" -eq 0 ]
    assert_contains "$output" "no readable version"
    assert_contains "$(cat "$BIN/npm.args")" "@anthropic-ai/claude-code@2.1.259"
}

@test "install-claude-cli: an install that leaves the wrong version fails loudly" {
    # npm succeeds but an older copy still wins on PATH. Scoring with an
    # unpinned CLI is exactly what must not happen quietly.
    stub_claude "1.0.0"
    printf '#!/bin/sh\nexit 0\n' > "$BIN/npm"   # installs nothing
    chmod +x "$BIN/npm"
    run_install "2.1.259"
    [ "$status" -ne 0 ]
    assert_contains "$output" "refusing to score with an unpinned CLI"
}

@test "install-claude-cli: a failing npm install fails the step" {
    printf '#!/bin/sh\nexit 1\n' > "$BIN/npm"
    chmod +x "$BIN/npm"
    run_install "2.1.259"
    [ "$status" -ne 0 ]
}

@test "install-claude-cli: jq missing is reported before the version check" {
    rm "$BIN/jq"
    stub_npm
    run_install "2.1.259"
    [ "$status" -ne 0 ]
    assert_contains "$output" "jq is required"
}

@test "action.yml delegates the install to the tested script" {
    # Inline `run:` shell in a composite action is untestable, which is how
    # the pin bypass survived review. Keep the logic in the script.
    grep -q 'bin/install-claude-cli.sh' "$REPO_ROOT/action.yml"
    run grep -c 'npm install' "$REPO_ROOT/action.yml"
    [ "$output" = "0" ]
}
