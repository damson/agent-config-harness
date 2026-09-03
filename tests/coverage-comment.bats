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

@test "coverage-comment: dry run renders total, worst file first, repo-relative paths" {
    run "$REPO_ROOT/bin/post-coverage-comment.sh" 7 "$COV" --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "81.25% (130/160 lines)"
    assert_contains "$output" '`bin/setup.sh`'
    # worst-first ordering: common.sh's row must appear before setup.sh's
    first=$(printf '%s\n' "$output" | grep -n 'common.sh\|setup.sh' | head -1)
    assert_contains "$first" "common.sh"
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
