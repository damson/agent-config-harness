#!/usr/bin/env bats
#
# Tests for the half of the eval the harness owns: turning findings into the
# five numbers, and never losing a reply on the way to disk.
#
# No model is called. The deduction rule is pure jq, so it is tested directly
# with synthetic findings, which is the only way to know the rubric's table and
# the code agree.

load helpers/common

setup() {
    cd "$REPO_ROOT"
    WORK=$(mktemp -d)
}

teardown() {
    rm -rf "$WORK"
}

# Build a result holding the given findings, run derive_scores over it, print
# the five scores plus the total and grade.
derive() {
    local findings="$1"
    cat > "$WORK/r.json" <<EOF
{"date":"2026-01-01T00:00:00Z","domain":"acme","git_hash":"x","scores":{"clarity":1,"conciseness":1,"completeness":1,"consistency":1,"actionability":1},"total":5,"percentage":20,"grade":"F","findings":$findings}
EOF
    run bash -c ". lib/common.sh; . lib/scoring.sh; derive_scores '$WORK/r.json' && jq -c '{s:.scores,t:.total,g:.grade}' '$WORK/r.json'"
}

@test "derive: a stack with nothing against it scores 25" {
    derive '[]'
    [ "$status" -eq 0 ]
    assert_contains "$output" '"t":25'
    assert_contains "$output" '"g":"A"'
}

@test "derive: one minor costs a point, one major costs three" {
    derive '[{"dimension":"clarity","severity":"minor"},{"dimension":"conciseness","severity":"major"}]'
    [ "$status" -eq 0 ]
    assert_contains "$output" '"clarity":4'
    assert_contains "$output" '"conciseness":2'
    assert_contains "$output" '"t":21'
}

@test "derive: majors dominate, and a second one floors the dimension" {
    # The ladder this replaced could not express a bad file: the repo's own
    # degraded example scored B under it.
    derive '[{"dimension":"clarity","severity":"major"},{"dimension":"clarity","severity":"major"},{"dimension":"clarity","severity":"minor"}]'
    [ "$status" -eq 0 ]
    assert_contains "$output" '"clarity":1'
}

@test "derive: two minors in one dimension are worse than one" {
    derive '[{"dimension":"completeness","severity":"minor"},{"dimension":"completeness","severity":"minor"}]'
    [ "$status" -eq 0 ]
    assert_contains "$output" '"completeness":3'
}

@test "derive: an untagged finding counts as major, so an omission cannot flatter" {
    derive '[{"dimension":"consistency","file":"x","section":"-","issue":"y","recommendation":"z"}]'
    [ "$status" -eq 0 ]
    assert_contains "$output" '"consistency":2'
}

@test "derive: the rot the repo ships as its worst case still fails" {
    # The shape of evals/examples/degraded.md: a contradiction, a section of
    # verbatim restatement, and platitudes in two dimensions. This is the
    # arithmetic half of `just calibrate`, and it runs in CI where that cannot.
    derive '[{"dimension":"consistency","severity":"major"},{"dimension":"conciseness","severity":"major"},{"dimension":"clarity","severity":"major"},{"dimension":"actionability","severity":"major"}]'
    [ "$status" -eq 0 ]
    assert_contains "$output" '"t":13'
    assert_contains "$output" '"g":"F"'
}

@test "derive: the grade boundaries match the rubric's table" {
    derive '[{"dimension":"clarity","severity":"minor"},{"dimension":"conciseness","severity":"minor"}]'
    assert_contains "$output" '"t":23'
    assert_contains "$output" '"g":"A"'
    derive '[{"dimension":"clarity","severity":"major"},{"dimension":"conciseness","severity":"minor"}]'
    assert_contains "$output" '"t":21'
    assert_contains "$output" '"g":"B"'
    derive '[{"dimension":"clarity","severity":"major"},{"dimension":"conciseness","severity":"major"}]'
    assert_contains "$output" '"t":19'
    assert_contains "$output" '"g":"C"'
}

@test "derive: the rule's jq is marked as foreign source, not as unrun bash" {
    # kcov counts every line of a multi-line literal as a statement bash never
    # executed. Unmarked, this one statement reported 27 uncovered lines and
    # took lib/scoring.sh from 92% to 61%, which is a number no test can move
    # and which sends the next reader off to write tests for code that seven
    # already cover.
    local lib="$REPO_ROOT/lib/scoring.sh"
    # This asserts WHERE the markers are, not that they exist. A region is only
    # right if it covers the jq program and neither shell line around it: kcov
    # excludes its stop line too, so an end marker one line lower stops
    # measuring the statement that decides whether the rule ran at all.
    #
    # One assertion per line: `[ -n "$a" ] && [ -n "$b" ]` does not abort a bats
    # test when it fails, so the next line errors on an empty integer and the
    # report blames the comparison rather than the missing marker.
    start=$(grep -n 'kcov-ignore-start' "$lib" | head -1 | cut -d: -f1)
    end=$(grep -n 'kcov-ignore-end' "$lib" | head -1 | cut -d: -f1)
    [ -n "$start" ]
    [ -n "$end" ]
    [ "$start" -lt "$end" ]

    # The jq program's own lines are inside the region.
    body=$(grep -n 'def dim_score' "$lib" | head -1 | cut -d: -f1)
    [ -n "$body" ]
    [ "$body" -gt "$start" ]
    [ "$body" -lt "$end" ]

    # The two shell lines are outside it: the `if` that opens the literal, and
    # the line that closes it and carries `; then`.
    opens=$(grep -n 'if ! jq' "$lib" | head -1 | cut -d: -f1)
    [ -n "$opens" ]
    [ "$opens" -lt "$start" ]
    # Anchored on the line that closes THIS literal, not on the next `; then`
    # anywhere in the file: there are nine of those, so a loose match finds one
    # below any end marker and passes on the very placement this rejects.
    closes=$(grep -n "^[[:space:]]*' \"\$file\"" "$lib" | head -1 | cut -d: -f1)
    [ -n "$closes" ]
    [ "$closes" -gt "$end" ]

    # And the region still covers only the program, not the function around it.
    [ $((end - start)) -lt 40 ]
}
