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

# `gh` that records argv and answers the comment-list call with real JSON.
#
# It answers in PAGES, the way `gh api --paginate` does: one page holding a
# decoy that must never be selected, then one page per id in $GH_COMMENT_IDS
# (or the single $GH_COMMENT_ID). Pages matter here, because the bug being
# guarded against only appears when matches fall on different ones.
make_gh_stub() {
    local bin="$1"
    mkdir -p "$bin"
    cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
if [ "$1" = "api" ] && [ "$2" != "-X" ]; then
    printf '[{"id":1,"body":"unrelated comment, must not be selected"}]\n'
    ids="${GH_COMMENT_IDS:-${GH_COMMENT_ID:-}}"
    for id in $ids; do
        printf '[{"id":%s,"body":"<!-- coverage-report -->\\nprevious body"}]\n' "$id"
    done
    exit 0
fi
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
    run env GITHUB_BASE_REF=develop \
        "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --base "$COV/base.json" --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "▲ +6.1 vs develop"
    assert_contains "$output" "🟩"
}

@test "coverage-comment: a higher baseline yields a down-arrow and red lost blocks" {
    printf '{"percent_covered":"92.25","covered_lines":148,"total_lines":160}' > "$COV/base.json"
    run env GITHUB_BASE_REF=develop \
        "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --base "$COV/base.json" --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "▼ -11.0 vs develop"
    assert_contains "$output" "🟥"
}

@test "coverage-comment: a sub-epsilon wobble prints unchanged, not an arrow" {
    printf '{"percent_covered":"81.27","covered_lines":130,"total_lines":160}' > "$COV/base.json"
    run env GITHUB_BASE_REF=develop \
        "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --base "$COV/base.json" --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "unchanged vs develop"
    ! grep -q '▲\|▼' <<<"$output"
}

@test "coverage-comment: the delta names the base branch it was measured against" {
    # The release pull request's base is main, not develop. The figure is
    # already measured against whatever baseline the caller passed; this
    # asserts the caption follows it instead of naming develop by habit.
    printf '{"percent_covered":"75.15","covered_lines":120,"total_lines":160}' > "$COV/base.json"
    run env GITHUB_BASE_REF=main \
        "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --base "$COV/base.json" --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "▲ +6.1 vs main"
    assert_not_contains "$output" "vs develop"
}

@test "coverage-comment: with no base ref in the environment the delta names no branch" {
    # Run outside a pull request there is no base to name. Better to say so
    # than to assert a branch that may not be the one measured.
    printf '{"percent_covered":"75.15","covered_lines":120,"total_lines":160}' > "$COV/base.json"
    run env -u GITHUB_BASE_REF \
        "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --base "$COV/base.json" --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "▲ +6.1 vs the base branch"
    assert_not_contains "$output" "vs develop"
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

@test "coverage-comment: a marker comment on a later page is still found" {
    # Regression: --paginate runs --jq once per page and concatenates, so a
    # match on any page but the first produced a usable-looking id that was
    # really one line of several, and the PATCH URL was malformed.
    run env PATH="$BIN:$PATH" GH_COMMENT_ID="4242" \
        "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV"
    [ "$status" -eq 0 ]
    assert_contains "$(cat "$GH_CALLS")" "-X PATCH repos/owner/repo/issues/comments/4242"
    ! grep -q -- '-X POST' "$GH_CALLS"
}

@test "coverage-comment: two marker comments are refused, not guessed between" {
    # Overwriting one of several is silent and unrecoverable, so stop instead.
    run env PATH="$BIN:$PATH" GH_COMMENT_IDS="4242 4343" \
        "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV"
    [ "$status" -ne 0 ]
    assert_contains "$output" "refusing to guess"
    ! grep -q -- '-X PATCH' "$GH_CALLS"
    ! grep -q -- '-X POST' "$GH_CALLS"
}

@test "coverage-comment: per-file paths are relative even when REPO_ROOT differs" {
    # Regression: the table stripped $REPO_ROOT, but kcov roots its paths at
    # the checkout it measured. Where the two differ the strip no-opped and
    # every row rendered an absolute path. Point AGENT_CONFIG_ROOT somewhere
    # else entirely, which is exactly the consumer case.
    local elsewhere
    elsewhere=$(mktemp -d)
    run env PATH="$BIN:$PATH" AGENT_CONFIG_ROOT="$elsewhere" \
        "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --dry-run
    rm -rf "$elsewhere"
    [ "$status" -eq 0 ]
    assert_contains "$output" '`bin/setup.sh`'
    assert_contains "$output" '`lib/common.sh`'
    assert_not_contains "$output" "\`$REPO_ROOT/bin/setup.sh\`"
}

@test "coverage-comment: coverage.json one level down is found, not missed" {
    # kcov only sometimes leaves a kcov-merged directory, so a caller can point
    # at the right parent and still not have the file directly beneath it.
    local outer
    outer=$(mktemp -d)
    make_coverage_json "$outer/kcov-merged"
    run env PATH="$BIN:$PATH" "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$outer" --dry-run
    rm -rf "$outer"
    [ "$status" -eq 0 ]
    assert_contains "$output" "Coverage: 81.25%"
}

@test "coverage-comment: a report deeper than one level down is a clear miss, not a silent one" {
    # The search is bounded on purpose: sweeping a whole checkout can match an
    # unrelated coverage.json and turn "not found" into a puzzling "several
    # found". What matters is that the boundary is stated rather than silent.
    local outer
    outer=$(mktemp -d)
    make_coverage_json "$outer/a/b/c"
    run env PATH="$BIN:$PATH" "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$outer" --dry-run
    rm -rf "$outer"
    [ "$status" -ne 0 ]
    assert_contains "$output" "one level below"
}

@test "coverage-comment: a directory named coverage.json is not mistaken for a report" {
    local outer
    outer=$(mktemp -d)
    mkdir -p "$outer/kcov-merged/coverage.json"
    run env PATH="$BIN:$PATH" "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$outer" --dry-run
    rm -rf "$outer"
    [ "$status" -ne 0 ]
    assert_contains "$output" "coverage.json"
}

@test "coverage-comment: several coverage.json files are refused, not guessed between" {
    # Picking one would report a single traced child's lines as the whole run.
    local outer
    outer=$(mktemp -d)
    make_coverage_json "$outer/bash.1111"
    make_coverage_json "$outer/bash.2222"
    run env PATH="$BIN:$PATH" "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$outer" --dry-run
    rm -rf "$outer"
    [ "$status" -ne 0 ]
    assert_contains "$output" "refusing to report one child as the run"
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

# The coverage workflow's push.branches, comma-separated. Scoped to the push
# mapping: a file-wide grep for "branches:" would be satisfied by a line under
# another event while push itself had lost a branch.
push_branches() {
    awk '
        /^on:[[:space:]]*$/            { in_on = 1; next }
        in_on && /^[^[:space:]#]/      { in_on = 0 }
        in_on && /^[[:space:]]+push:/  { in_push = 1; next }
        in_push && /^[[:space:]]{2}[^[:space:]#]/ { in_push = 0 }
        in_push && /branches:/ {
            sub(/^[^[]*\[/, ""); sub(/\].*$/, ""); gsub(/[[:space:]]/, "")
            print; exit
        }
    ' "$REPO_ROOT/.github/workflows/coverage.yml"
}

@test "coverage workflow: no back-merge special case survives" {
    # The routine back-merge is a fast-forward now and opens no pull request,
    # so there is nothing to skip. A leftover head_ref condition here would
    # silently stop measuring some other PR, so assert the job carries no
    # branch-specific gate at all.
    require_python_yaml
    run python3 -c '
import sys, yaml
job = yaml.safe_load(open(sys.argv[1]))["jobs"]["coverage"]
sys.exit(1 if "head_ref" in str(job.get("if", "")) else 0)
' "$REPO_ROOT/.github/workflows/coverage.yml"
    [ "$status" -eq 0 ]
}

@test "coverage badge: the README names a branch the workflow measures" {
    # A badge pointing at an unmeasured branch renders "unknown" and nobody
    # notices, because the README is not what CI looks at. Pin the pair
    # rather than the literal branch: what matters is that they agree.
    local branch measured
    branch=$(grep -oE 'codecov\.io/gh/[^)]*/branch/[a-zA-Z0-9._/-]+/graph' "$REPO_ROOT/README.md" \
        | head -1 | sed -E 's|.*/branch/([^/]+)/graph|\1|')
    [ -n "$branch" ]
    measured=$(push_branches)
    [ -n "$measured" ]
    printf '%s\n' "$measured" | tr ',' '\n' | grep -qx "$branch"
}

@test "coverage workflow: both long-lived branches are measured on push" {
    # Codecov diffs a PR against a report for its BASE commit. develop is the
    # base of every feature PR; main is the base of the release PR, and with
    # no report there the release comment reads "Coverage ? -> nn%" with no
    # delta, on the one PR where the delta matters most.
    local measured
    measured=$(push_branches)
    printf '%s\n' "$measured" | tr ',' '\n' | grep -qx develop
    printf '%s\n' "$measured" | tr ',' '\n' | grep -qx main
}

@test "coverage workflow: the lines inside quoted programs are excluded from measurement" {
    # kcov's bash parser counts the body of a multi-line awk or jq program as
    # bash lines, and they can never be hit: they are awk and jq source, run by
    # a different interpreter. Left in, they report as permanently uncovered
    # code that no test can reach, which understates the figure and puts a
    # patch-coverage failure on any PR that touches one.
    #
    # The exclusion is what makes the kcov-ignore markers in the sources mean
    # anything. Without the flag they are inert comments and the phantom lines
    # come straight back, so assert the flag and the markers together.
    local wf="$REPO_ROOT/.github/workflows/coverage.yml"
    grep -q -- '--exclude-region=kcov-ignore-start:kcov-ignore-end' "$wf"

    # One region per embedded program in the file: the delta and band awk
    # programs, the per-file jq program, and the awk that derives the path
    # prefix. An exact count rather than a floor, so removing a region fails
    # here instead of quietly restoring the phantom lines.
    local marked
    marked=$(grep -c 'kcov-ignore-start' "$REPO_ROOT/bin/post-coverage-comment.sh")
    [ "$marked" -eq 4 ]
    assert_equal_count "$REPO_ROOT/bin/post-coverage-comment.sh"
}

# Every opened region must be closed, or kcov swallows the rest of the file
# silently: the run stays green and the coverage simply drops lines nobody
# asked it to drop.
assert_equal_count() {
    local f="$1" starts ends
    starts=$(grep -c 'kcov-ignore-start' "$f")
    ends=$(grep -c 'kcov-ignore-end' "$f")
    [ "$starts" -eq "$ends" ]
}
