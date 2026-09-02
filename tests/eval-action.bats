#!/usr/bin/env bats
#
# Tests for bin/eval-action.sh — the CI entry point behind the root action.yml.
#
# Nothing here calls the real Claude CLI: a stub `claude` on PATH returns a
# canned result whose grade the test controls, so what is under test is the
# mode selection (synth root vs consumer registry), the threshold gate, and
# that the repo being scored is never written to.

load helpers/common

setup() {
    TARGET=$(mktemp -d)
    printf '# My project\n\n- A rule.\n' > "$TARGET/CLAUDE.md"

    STUB=$(mktemp -d)
    printf 'B\n' > "$STUB/grade"
    cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
# Canned eval reply; the grade comes from the file beside this stub.
g=$(cat "$(dirname "$0")/grade")
cat <<JSON
{"date":"2026-01-01","domain":"stub","git_hash":"stub","scores":{"clarity":5},"total":22,"percentage":88,"grade":"$g","findings":[]}
JSON
EOF
    chmod +x "$STUB/claude"
}

teardown() {
    rm -rf "$TARGET" "$STUB"
}

run_action() {
    run env PATH="$STUB:$PATH" TARGET_DIR="$TARGET" "$@" "$REPO_ROOT/bin/eval-action.sh"
}

@test "eval action: scores a plain repo's CLAUDE.md and passes at the threshold" {
    run_action FAIL_BELOW=C
    [ "$status" -eq 0 ]
    assert_contains "$output" "grade B"
}

@test "eval action: fails when the grade is below the threshold" {
    printf 'D\n' > "$STUB/grade"
    run_action FAIL_BELOW=C
    [ "$status" -ne 0 ]
    assert_contains "$output" "below the C threshold"
}

@test "eval action: a grade equal to the threshold passes — below means below" {
    printf 'C\n' > "$STUB/grade"
    run_action FAIL_BELOW=C
    [ "$status" -eq 0 ]
}

@test "eval action: a missing file is a hard error, not a vacuous pass" {
    run_action EVAL_FILES=NOPE.md
    [ "$status" -ne 0 ]
    assert_contains "$output" "No such file"
}

@test "eval action: never writes into the repo being scored" {
    run_action FAIL_BELOW=C
    [ "$status" -eq 0 ]
    run bash -c "ls -A '$TARGET'"
    [ "$output" = "CLAUDE.md" ]
}

@test "eval action: registry mode scores the consumer's own domain in place" {
    mkdir -p "$TARGET/config" "$TARGET/workspace/acme"
    printf 'acme = workspace/acme : CLAUDE.md\n' > "$TARGET/config/domains.conf"
    printf '# Acme\n\n- A rule.\n' > "$TARGET/workspace/acme/CLAUDE.md"
    run_action EVAL_DOMAIN=acme
    [ "$status" -eq 0 ]
    run bash -c "ls '$TARGET/evals/results/' | head -1"
    assert_contains "$output" "acme.json"
}
