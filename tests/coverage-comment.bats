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

@test "coverage workflow: the back-merge PR does not run coverage" {
    # A back-merge PR carries an empty diff and is merged as soon as it is
    # green. The merge deletes the PR's merge ref while the 10-minute run is
    # still going, and GitHub reports that as a failed run with no jobs, which
    # is an artifact nobody can act on. main's own push run measures the same
    # commit anyway.
    require_python_yaml
    # Assert what the predicate DOES, for the three input combinations that
    # matter, rather than what it says. A substring check passes for the
    # inverted `head_ref == 'main'`, which skips coverage everywhere except
    # the back-merge: the exact opposite of the intent.
    run python3 -c '
import sys, yaml
cond = yaml.safe_load(open(sys.argv[1]))["jobs"]["coverage"].get("if", "")
if not cond:
    sys.exit(1)

def fires(event, head):
    """Does the job run for this (event, head branch) pair?"""
    expr = (cond.replace("github.event_name", repr(event))
                .replace("github.head_ref", repr(head))
                .replace("||", " or ").replace("&&", " and ").replace("!", " not "))
    expr = expr.replace(" not =", " !=")   # undo the ! we just mangled in !=
    return bool(eval(expr))

sys.exit(0 if (not fires("pull_request", "main")     # the back-merge: skipped
               and fires("pull_request", "feature/x")  # every other PR: runs
               and fires("push", "main")               # main push: runs
               and fires("push", "develop")) else 1)   # develop push: runs
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
