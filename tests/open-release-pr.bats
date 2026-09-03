#!/usr/bin/env bats
#
# Tests for bin/open-release-pr.sh — the weekly develop → main PR.
#
# Every case runs the real script against a throwaway repo, with `gh` stubbed
# onto PATH so the calls it would make are recorded instead of sent.

load helpers/common

# A repo with origin/main and origin/develop as local remote-tracking refs, so
# the script's range works without a network.
make_repo() {
    local ahead="$1" dir
    dir=$(mktemp -d)
    (
        cd "$dir"
        git init -q .
        git config user.email t@t
        git config user.name T
        git commit -q --allow-empty -m "base"
        git update-ref refs/remotes/origin/main HEAD
        if [ "$ahead" -gt 0 ]; then
            git checkout -q -b feature
            git commit -q --allow-empty -m "a change worth releasing"
            git checkout -q -
            git merge -q --no-ff feature -m "Merge pull request #99 from owner/feature"
        fi
        git update-ref refs/remotes/origin/develop HEAD
    )
    printf '%s' "$dir"
}

# `gh` that records its arguments and answers `pr list` with $GH_EXISTING_PR.
make_gh_stub() {
    local bin="$1"
    mkdir -p "$bin"
    cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
    printf '%s' "${GH_EXISTING_PR:-}"
fi
exit 0
STUB
    chmod +x "$bin/gh"
}

setup() {
    REPO=$(make_repo "${AHEAD:-1}")
    BIN=$(mktemp -d)
    make_gh_stub "$BIN"
    export GH_CALLS="$BIN/calls.log"
    : > "$GH_CALLS"
}

teardown() {
    rm -rf "$REPO" "$BIN"
}

@test "open-release-pr: does nothing when develop is not ahead of main" {
    local repo
    repo=$(make_repo 0)
    run env PATH="$BIN:$PATH" bash -c "cd '$repo' && '$REPO_ROOT/bin/open-release-pr.sh'"
    [ "$status" -eq 0 ]
    assert_contains "$output" "nothing to release"
    [ ! -s "$GH_CALLS" ]     # no PR opened, no PR edited
    rm -rf "$repo"
}

@test "open-release-pr: opens a PR when none is open" {
    run env PATH="$BIN:$PATH" GH_EXISTING_PR="" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-release-pr.sh'"
    [ "$status" -eq 0 ]
    grep -q 'pr create --base main --head develop' "$GH_CALLS"
    ! grep -q 'pr edit' "$GH_CALLS"
}

@test "open-release-pr: refreshes the open PR instead of opening a second one" {
    run env PATH="$BIN:$PATH" GH_EXISTING_PR="123" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-release-pr.sh'"
    [ "$status" -eq 0 ]
    grep -q 'pr edit 123' "$GH_CALLS"
    ! grep -q 'pr create' "$GH_CALLS"
}

@test "open-release-pr: the body carries the inventory and the mandatory diagram section" {
    run env PATH="$BIN:$PATH" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-release-pr.sh' --dry-run"
    [ "$status" -eq 0 ]
    # A release without a diagram section is the thing this whole PR prevents.
    assert_contains "$output" "## 📐 Before / after"
    assert_contains "$output" "#99"            # the merged PR was picked up
    # Two: the change itself and the merge commit that brought it in.
    assert_contains "$output" "Commits | 2"
    assert_contains "$output" "(no file changes)"   # stated, rather than a blank cell
}

@test "open-release-pr: a squash-merged PR is listed alongside merge-commit PRs" {
    (
        cd "$REPO"
        git commit -q --allow-empty -m "Tighten the flux capacitor (#123)"
        git update-ref refs/remotes/origin/develop HEAD
    )
    run env PATH="$BIN:$PATH" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-release-pr.sh' --dry-run"
    [ "$status" -eq 0 ]
    # Assert on the inventory row itself — the subjects list also prints
    # "(#123)", so a whole-output match could never fail.
    prs_row=$(printf '%s\n' "$output" | grep '| Pull requests |')
    assert_contains "$prs_row" "#123"   # squash subject "... (#123)"
    assert_contains "$prs_row" "#99"    # classic merge subject still picked up
}

@test "open-release-pr: --dry-run touches nothing" {
    run env PATH="$BIN:$PATH" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-release-pr.sh' --dry-run"
    [ "$status" -eq 0 ]
    [ ! -s "$GH_CALLS" ]
}
