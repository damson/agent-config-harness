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
    printf '22\n' > "$STUB/total"
    printf '[]\n' > "$STUB/findings"
    cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
# Canned eval reply; grade, total and findings come from files beside this
# stub, so a test can inject arbitrary (attacker-shaped) values.
g=$(cat "$(dirname "$0")/grade")
t=$(cat "$(dirname "$0")/total")
f=$(cat "$(dirname "$0")/findings")
cat <<JSON
{"date":"2026-01-01","domain":"stub","git_hash":"stub","scores":{"clarity":5},"total":$t,"percentage":88,"grade":"$g","findings":$f}
JSON
EOF
    chmod +x "$STUB/claude"
}

teardown() {
    rm -rf "$TARGET" "$STUB"
}

# GITHUB_OUTPUT / GITHUB_STEP_SUMMARY are blanked so a run inside real CI
# cannot write into the actual job's files; tests that assert on them pass
# their own paths via "$@", which wins because env's later assignment wins.
run_action() {
    run env PATH="$STUB:$PATH" TARGET_DIR="$TARGET" ANTHROPIC_API_KEY=stub-key \
        GITHUB_OUTPUT= GITHUB_STEP_SUMMARY= "$@" "$REPO_ROOT/bin/eval-action.sh"
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

@test "eval action: an empty ANTHROPIC_API_KEY is an early, explicit error" {
    run_action ANTHROPIC_API_KEY=
    [ "$status" -ne 0 ]
    assert_contains "$output" "ANTHROPIC_API_KEY is not set"
}

@test "eval action: an injected multi-line grade aborts before anything reaches GITHUB_OUTPUT" {
    # A JSON \n escape: jq -r turns it into a real newline, which — appended
    # raw — would smuggle a second variable into the consumer workflow.
    printf 'A\\nmalicious=1\n' > "$STUB/grade"
    : > "$STUB/gh_output"
    run_action GITHUB_OUTPUT="$STUB/gh_output"
    [ "$status" -ne 0 ]
    assert_contains "$output" "invalid grade"
    [ ! -s "$STUB/gh_output" ]
}

@test "eval action: a non-numeric total aborts before anything reaches GITHUB_OUTPUT" {
    printf '"22\\nsneaky=1"\n' > "$STUB/total"
    : > "$STUB/gh_output"
    run_action GITHUB_OUTPUT="$STUB/gh_output"
    [ "$status" -ne 0 ]
    assert_contains "$output" "invalid total"
    [ ! -s "$STUB/gh_output" ]
}

@test "eval action: findings are sanitized before reaching the step summary" {
    printf '%s\n' '[{"dimension":"clarity","file":"CLAUDE.md","section":"intro","issue":"click <a href=evil>here</a>\nsecond=line"}]' > "$STUB/findings"
    : > "$STUB/summary"
    run_action GITHUB_STEP_SUMMARY="$STUB/summary"
    [ "$status" -eq 0 ]
    summary=$(cat "$STUB/summary")
    assert_not_contains "$summary" "<a href"
    assert_contains "$summary" "&lt;a href"
    # The \n inside the finding is flattened to a space, not a new summary line.
    assert_contains "$summary" "here&lt;/a> second=line"
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
