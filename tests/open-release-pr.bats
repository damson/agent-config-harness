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

# `gh` that records its arguments, answers `pr list` with $GH_EXISTING_PR and
# `pr view` with $GH_PR_BODY, and saves whatever body it is asked to write to
# $GH_BODY, so a test can assert on the description rather than on the call.
make_gh_stub() {
    local bin="$1"
    mkdir -p "$bin"
    cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
    printf '%s' "${GH_EXISTING_PR:-}"
fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
    printf '%s' "${GH_PR_BODY:-}"
fi
if [ "$1" = "pr" ] && { [ "$2" = "edit" ] || [ "$2" = "create" ]; }; then
    prev=""
    for arg in "$@"; do
        [ "$prev" = "--body" ] && printf '%s' "$arg" > "$GH_BODY"
        prev="$arg"
    done
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
    export GH_BODY="$BIN/body.md"
    : > "$GH_CALLS"
    : > "$GH_BODY"
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

# --- Refreshing an open PR ---------------------------------------------------
# The refresh runs on every push to the integration branch now, not weekly, so
# a refresh that regenerated the whole body would discard the summary and the
# diagram several times a week. Only the generated block may be rewritten.

@test "open-release-pr: a refresh keeps the sections a human wrote" {
    export GH_PR_BODY='## 👥 High-level summary

This batch teaches the harness to stop lying about itself.

## 📐 Before / after

```mermaid
flowchart LR
    a --> b
```

---

## 📦 What is in this batch

| | |
|---|---|
| Commits | 999 |
'
    run env PATH="$BIN:$PATH" GH_EXISTING_PR="123" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-release-pr.sh'"
    [ "$status" -eq 0 ]
    local body
    body=$(cat "$GH_BODY")
    assert_contains "$body" "stop lying about itself"   # the summary survived
    assert_contains "$body" "flowchart LR"              # so did the diagram
    assert_contains "$body" "| Commits | 2 |"           # inventory is current
    assert_not_contains "$body" "999"                   # and the stale one is gone
}

@test "open-release-pr: refreshing a body it already wrote does not pile up" {
    # Feed the script its own output. A second marker or a second rule would
    # mean the body grows a copy of itself on every push.
    export GH_PR_BODY="$(env PATH="$BIN:$PATH" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-release-pr.sh' --dry-run")"
    run env PATH="$BIN:$PATH" GH_EXISTING_PR="123" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-release-pr.sh'"
    [ "$status" -eq 0 ]
    local markers rules
    markers=$(grep -c '^## 📦 What is in this batch$' "$GH_BODY")
    rules=$(grep -c '^---$' "$GH_BODY")
    [ "$markers" -eq 1 ]
    [ "$rules" -eq 1 ]
}

@test "open-release-pr: a body with no generated block is kept whole" {
    # Someone rewrote the description by hand. Guessing where the block would
    # have gone risks eating their text; appending never does.
    export GH_PR_BODY='Only a hand-written note, no marker anywhere.'
    run env PATH="$BIN:$PATH" GH_EXISTING_PR="123" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-release-pr.sh'"
    [ "$status" -eq 0 ]
    local body
    body=$(cat "$GH_BODY")
    assert_contains "$body" "Only a hand-written note"
    assert_contains "$body" "## 📦 What is in this batch"
}

@test "open-release-pr: an empty body falls back to the template" {
    export GH_PR_BODY=''
    run env PATH="$BIN:$PATH" GH_EXISTING_PR="123" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-release-pr.sh'"
    [ "$status" -eq 0 ]
    # The mandatory sections come back rather than the PR being left with only
    # a table under no headings at all.
    assert_contains "$(cat "$GH_BODY")" "## 📐 Before / after"
}

@test "open-release-pr: --dry-run touches nothing" {
    run env PATH="$BIN:$PATH" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-release-pr.sh' --dry-run"
    [ "$status" -eq 0 ]
    [ ! -s "$GH_CALLS" ]
}
