#!/usr/bin/env bats
#
# Tests for bin/calibrate-rubric.sh — the guard that asks whether the rubric can
# still tell a good config from a rotted one.
#
# The script's own value depends on it failing when the answer is no, so that is
# what these check, with a stub `claude` that answers differently per domain.

load helpers/common

setup() {
    cd "$REPO_ROOT"
    STUB=$(mktemp -d)
}

teardown() {
    rm -rf "$STUB"
}

# A stub that reads the assembled prompt and answers by the domain named in it.
# $1 is the total it gives the rotted file, $2 the total for the good one.
make_claude() {
    local rot_total="$1" good_total="$2"
    cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
prompt=\$(cat)
total=$good_total
case "\$prompt" in *"domain: rot"*) total=$rot_total ;; esac
printf '{"date":"2026-01-01T00:00:00Z","domain":"d","git_hash":"x","scores":{"clarity":5,"conciseness":5,"completeness":5,"consistency":5,"actionability":5},"total":%s,"percentage":80,"grade":"B","findings":[]}\n' "\$total"
EOF
    chmod +x "$STUB/claude"
}

# The script reads the totals from the result files, and run-eval.sh derives
# them from findings, so the stub's findings are what set the score. Findings
# that produce the totals above: none for the good file, four majors for the rot.
make_claude_findings() {
    cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
prompt=$(cat)
findings='[]'
case "$prompt" in *"domain: rot"*)
    findings='[{"dimension":"clarity","severity":"major","file":"f","section":"-","issue":"i","recommendation":"r"},{"dimension":"conciseness","severity":"major","file":"f","section":"-","issue":"i","recommendation":"r"},{"dimension":"consistency","severity":"major","file":"f","section":"-","issue":"i","recommendation":"r"},{"dimension":"actionability","severity":"major","file":"f","section":"-","issue":"i","recommendation":"r"}]' ;;
esac
printf '{"date":"2026-01-01T00:00:00Z","domain":"d","git_hash":"x","scores":{"clarity":5,"conciseness":5,"completeness":5,"consistency":5,"actionability":5},"total":25,"percentage":100,"grade":"A","findings":%s}\n' "$findings"
EOF
    chmod +x "$STUB/claude"
}

@test "calibrate: passes when the rubric still separates the pair" {
    make_claude_findings
    run env PATH="$STUB:$PATH" ./bin/calibrate-rubric.sh
    [ "$status" -eq 0 ]
    assert_contains "$output" "Calibration passed"
    assert_contains "$output" "good: 25/25"
    assert_contains "$output" "rot:  13/25"
}

@test "calibrate: fails when the rotted file scores respectably" {
    # The exact failure that shipped: a rubric made stable by making it blind.
    # Every dimension a 5 for both files, so the rot comes back at 25.
    make_claude 25 25
    run env PATH="$STUB:$PATH" ./bin/calibrate-rubric.sh
    [ "$status" -ne 0 ]
    assert_contains "$output" "cannot fail it cannot fail anything"
    assert_contains "$output" "Calibration failed"
}

@test "calibrate: fails when the gap is too narrow to act on" {
    # Good and rot both middling: no scores crossed a threshold, and the pair
    # still says nothing a reader could use.
    cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
prompt=$(cat)
findings='[{"dimension":"clarity","severity":"minor","file":"f","section":"-","issue":"i","recommendation":"r"}]'
case "$prompt" in *"domain: rot"*)
    findings='[{"dimension":"clarity","severity":"minor","file":"f","section":"-","issue":"i","recommendation":"r"},{"dimension":"conciseness","severity":"minor","file":"f","section":"-","issue":"i","recommendation":"r"}]' ;;
esac
printf '{"date":"2026-01-01T00:00:00Z","domain":"d","git_hash":"x","scores":{"clarity":5,"conciseness":5,"completeness":5,"consistency":5,"actionability":5},"total":25,"percentage":100,"grade":"A","findings":%s}\n' "$findings"
EOF
    chmod +x "$STUB/claude"
    run env PATH="$STUB:$PATH" ./bin/calibrate-rubric.sh
    [ "$status" -ne 0 ]
    assert_contains "$output" "gap is"
}

@test "calibrate: a run that produced no result is a failure, not a zero to ignore" {
    cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo "no json here" 
EOF
    chmod +x "$STUB/claude"
    run env PATH="$STUB:$PATH" ./bin/calibrate-rubric.sh
    [ "$status" -ne 0 ]
    assert_contains "$output" "Calibration failed"
}
