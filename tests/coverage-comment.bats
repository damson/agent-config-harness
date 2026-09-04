#!/usr/bin/env bats
#
# Tests for bin/post-coverage-comment.sh — the sticky PR coverage comment.
#
# The real script runs against a stubbed `gh`, so the upsert logic (create on
# first run, edit in place after) is exercised without a network.

load helpers/common

make_coverage_json() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/coverage.json" <<JSON
{
  "percent_covered": "81.25",
  "covered_lines": 130,
  "total_lines": 160,
  "files": [
    { "file": "$REPO_ROOT/bin/setup.sh", "percent_covered": "92.00", "covered_lines": 92, "total_lines": 100 },
    { "file": "$REPO_ROOT/lib/common.sh", "percent_covered": "63.33", "covered_lines": 38, "total_lines": 60 }
  ]
}
JSON
}

# `gh` that records argv and answers the comment-list call with $GH_COMMENTS.
make_gh_stub() {
    local bin="$1"
    mkdir -p "$bin"
    cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
for a in "$@"; do
    case "$a" in repos/*/issues/*/comments)
        if [ "$1" = "api" ] && [ "$2" != "-X" ]; then
            # the list call pipes through --jq inside the script; emulate the
            # post-jq answer directly
            printf '%s' "${GH_COMMENT_ID:-}"
            exit 0
        fi
    esac
done
exit 0
STUB
    chmod +x "$bin/gh"
}

setup() {
    COV=$(mktemp -d)
    BIN=$(mktemp -d)
    make_coverage_json "$COV"
    make_gh_stub "$BIN"
    export GH_CALLS="$BIN/calls.log"
    export GITHUB_REPOSITORY="owner/repo"
    : > "$GH_CALLS"
}

teardown() {
    rm -rf "$COV" "$BIN"
}

@test "coverage-comment: dry run renders headline, denominator, worst file first" {
    run "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "81.25% of lines"
    assert_contains "$output" "130/160 lines"
    assert_contains "$output" '`bin/setup.sh`'
    # worst-first ordering: common.sh's row must appear before setup.sh's
    first=$(printf '%s\n' "$output" | grep -n 'common.sh\|setup.sh' | head -1)
    assert_contains "$first" "common.sh"
}

@test "coverage-comment: no baseline says so and paints a plain bar" {
    run "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "no baseline, first measured run"
    assert_contains "$output" "🟦"
    ! grep -q '🟩\|🟥' <<<"$output"
}

@test "coverage-comment: a lower baseline yields an up-arrow delta and green gain blocks" {
    printf '{"percent_covered":"75.15","covered_lines":120,"total_lines":160}' > "$COV/base.json"
    run "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --base "$COV/base.json" --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "▲ +6.1 vs develop"
    assert_contains "$output" "🟩"
}

@test "coverage-comment: a higher baseline yields a down-arrow and red lost blocks" {
    printf '{"percent_covered":"92.25","covered_lines":148,"total_lines":160}' > "$COV/base.json"
    run "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --base "$COV/base.json" --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "▼ -11.0 vs develop"
    assert_contains "$output" "🟥"
}

@test "coverage-comment: a sub-epsilon wobble prints unchanged, not an arrow" {
    printf '{"percent_covered":"81.27","covered_lines":130,"total_lines":160}' > "$COV/base.json"
    run "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --base "$COV/base.json" --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "unchanged vs develop"
    ! grep -q '▲\|▼' <<<"$output"
}

@test "coverage-comment: the band respects the configured floor and target" {
    run env COVERAGE_FLOOR=90 COVERAGE_TARGET=95 \
        "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "🔴 **Below floor**"
    run "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --dry-run
    assert_contains "$output" "🟢 **At target**"
}

@test "coverage-comment: no existing comment → POST to the PR" {
    run env PATH="$BIN:$PATH" GH_COMMENT_ID="" "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV"
    [ "$status" -eq 0 ]
    assert_contains "$(cat "$GH_CALLS")" "-X POST repos/owner/repo/issues/7/comments"
}

@test "coverage-comment: marker found → PATCH the same comment, no new one" {
    run env PATH="$BIN:$PATH" GH_COMMENT_ID="4242" "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV"
    [ "$status" -eq 0 ]
    assert_contains "$(cat "$GH_CALLS")" "-X PATCH repos/owner/repo/issues/comments/4242"
    ! grep -q -- '-X POST' "$GH_CALLS"
}

@test "coverage-comment: missing coverage.json is a loud failure" {
    empty=$(mktemp -d)
    run "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$empty"
    rm -rf "$empty"
    [ "$status" -ne 0 ]
    assert_contains "$output" "coverage.json"
}

@test "coverage-comment: a non-numeric PR argument is rejected" {
    run "$REPO_ROOT/bin/post-coverage-comment.sh" "abc" "$COV"
    [ "$status" -ne 0 ]
}

@test "coverage workflow: kcov's output directory is absolute" {
    # kcov passes the output dir to every traced child exactly as given, so a
    # relative one is re-resolved against that child's cwd. Tests that cd into
    # a temp fixture then write their coverage fragments inside the fixture,
    # and teardown deletes them: the tests still pass while their lines never
    # arrive. Measured on tests/git-stealth.bats — 10/81 lines relative,
    # 77/81 absolute.
    local wf="$REPO_ROOT/.github/workflows/coverage.yml"
    grep -qE '"\$PWD/coverage-out"' "$wf"
    # And no bare relative form survives as the kcov argument.
    run grep -nE '^[[:space:]]+coverage-out ' "$wf"
    [ "$status" -ne 0 ]
}

@test "coverage workflow: both long-lived branches are measured on push" {
    # Codecov diffs a PR against a report for its BASE commit. develop is the
    # base of every feature PR; main is the base of the release PR, and with
    # no report there the release comment reads "Coverage ? -> nn%" with no
    # delta, on the one PR where the delta matters most.
    local wf="$REPO_ROOT/.github/workflows/coverage.yml"
    run grep -E '^\s+branches: \[develop, main\]' "$wf"
    [ "$status" -eq 0 ]
}
