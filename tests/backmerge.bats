#!/usr/bin/env bats
#
# Tests for bin/backmerge.sh — bringing develop level with main after a release.
#
# The fixture is a real bare repository served over the filesystem, not faked
# remote refs, because the routine path is now a push: asserting that develop
# actually moved is the only assertion that means anything. `gh` is stubbed so
# the fallback path records its calls instead of sending them.

load helpers/common

# make_repo <shape> — build an origin plus a working clone, print the clone.
#
#   level     develop already contains main
#   release   main ahead by a release merge commit, no file changes
#   hotfix    main ahead by an original commit, trees differ
#   diverged  main ahead by a release merge AND develop ahead by its own commit
make_repo() {
    local shape="$1" root origin work
    root=$(mktemp -d)
    origin="$root/origin.git"
    work="$root/work"

    git init -q --bare -b main "$origin"
    git clone -q "$origin" "$work" 2>/dev/null
    (
        cd "$work"
        git config user.email t@t
        git config user.name T
        git commit -q --allow-empty -m "base"
        git push -q origin HEAD:refs/heads/main
        git push -q origin HEAD:refs/heads/develop

        # A release, faithfully: the work is committed on develop and main
        # gains only the MERGE commit. Committing straight onto main instead
        # would leave a non-merge commit there, which the script correctly
        # reads as original work, so the fixture has to do it properly or it
        # tests the hotfix path by accident.
        release_shape() {
            git checkout -q -B dev origin/develop
            echo work > work.txt
            git add work.txt
            git commit -q -m "A feature"
            git push -q origin HEAD:refs/heads/develop
            git checkout -q -B rel origin/main
            git merge -q --no-ff dev -m "Merge pull request #66 from owner/develop"
            git push -q origin HEAD:refs/heads/main
        }

        case "$shape" in
            level) : ;;
            release) release_shape ;;
            hotfix)
                echo hotfix > hotfix.txt
                git add hotfix.txt
                git commit -q -m "Hotfix applied directly to main"
                git push -q origin HEAD:refs/heads/main
                ;;
            diverged)
                release_shape
                git checkout -q -B dev origin/develop
                git commit -q --allow-empty -m "A feature landed on develop meanwhile"
                git push -q origin HEAD:refs/heads/develop
                ;;
        esac
        git fetch -q origin
    )
    printf '%s' "$work"
}

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
    BIN=$(mktemp -d)
    make_gh_stub "$BIN"
    export GH_CALLS="$BIN/calls.log"
    : > "$GH_CALLS"
}

teardown() {
    rm -rf "$BIN" "${REPO:-}" "${REPO%/work}"
}

run_backmerge() {
    run env PATH="$BIN:$PATH" bash -c "cd '$REPO' && '$REPO_ROOT/bin/backmerge.sh' $*"
}

# origin's develop, as the bare repo has it.
origin_develop() {
    git -C "$REPO" ls-remote origin refs/heads/develop | cut -f1
}
origin_main() {
    git -C "$REPO" ls-remote origin refs/heads/main | cut -f1
}

# ── Nothing to do ─────────────────────────────────────────

@test "backmerge: does nothing when develop already contains main" {
    REPO=$(make_repo level)
    local before
    before=$(origin_develop)
    run_backmerge
    [ "$status" -eq 0 ]
    assert_contains "$output" "already contains"
    [ "$(origin_develop)" = "$before" ]
    [ ! -s "$GH_CALLS" ]
}

# ── The routine path is a push ────────────────────────────

@test "backmerge: fast-forwards develop to main" {
    REPO=$(make_repo release)
    run_backmerge
    [ "$status" -eq 0 ]
    assert_contains "$output" "Fast-forwarded"
    # The assertion that matters: origin's develop now IS main.
    [ "$(origin_develop)" = "$(origin_main)" ]
}

@test "backmerge: the routine case opens no pull request" {
    # The whole point of the rework. A pull request here is one nobody can
    # review, and its held workflow runs were recorded as failures.
    REPO=$(make_repo release)
    run_backmerge
    [ "$status" -eq 0 ]
    [ ! -s "$GH_CALLS" ]
}

@test "backmerge: a routine back-merge is reported as history only" {
    REPO=$(make_repo release)
    run_backmerge
    [ "$status" -eq 0 ]
    assert_contains "$output" "no file changes"
}

@test "backmerge: --dry-run reports the fast-forward and pushes nothing" {
    REPO=$(make_repo release)
    local before
    before=$(origin_develop)
    run_backmerge --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "Would fast-forward"
    [ "$(origin_develop)" = "$before" ]
    [ ! -s "$GH_CALLS" ]
}

@test "backmerge: a hotfix on main is announced, and still carried across" {
    # A hotfix reached main through its own reviewed pull request, so bringing
    # it to develop is not unexamined content. It must be said out loud, and it
    # must actually arrive.
    REPO=$(make_repo hotfix)
    run_backmerge
    [ "$status" -eq 0 ]
    assert_contains "$output" "commit(s) of its own"
    assert_contains "$output" "Hotfix applied directly to main"
    [ "$(origin_develop)" = "$(origin_main)" ]
}

# ── The one case that still needs a pull request ──────────

@test "backmerge: opens a PR when develop has moved on" {
    # No longer a fast-forward: levelling the two needs a merge commit somebody
    # authors, and authoring is what review is for.
    REPO=$(make_repo diverged)
    local before
    before=$(origin_develop)
    run_backmerge
    [ "$status" -eq 0 ]
    assert_contains "$output" "cannot be a fast-forward"
    assert_contains "$(cat "$GH_CALLS")" "pr create"
    # and it did NOT quietly push instead
    [ "$(origin_develop)" = "$before" ]
}

@test "backmerge: the fallback PR opens from main into develop, not the reverse" {
    REPO=$(make_repo diverged)
    run_backmerge
    assert_contains "$(cat "$GH_CALLS")" "--base develop --head main"
}

@test "backmerge: refreshes the open fallback PR instead of opening a second" {
    REPO=$(make_repo diverged)
    GH_EXISTING_PR=42 run env PATH="$BIN:$PATH" GH_EXISTING_PR=42 \
        bash -c "cd '$REPO' && '$REPO_ROOT/bin/backmerge.sh'"
    assert_contains "$(cat "$GH_CALLS")" "pr edit 42"
    ! grep -q 'pr create' "$GH_CALLS"
}

@test "backmerge: the fallback PR body tells a reader to approve its held runs" {
    # A PR opened by a workflow has its runs held for approval. This is the one
    # back-merge with something to test, so the body must say so.
    REPO=$(make_repo diverged)
    run_backmerge --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "held for approval"
    assert_contains "$output" "History only"
}

@test "backmerge: the fallback PR body names a hotfix as carrying file changes" {
    REPO=$(make_repo diverged)
    # Put an original commit on main as well, so the fallback path sees both.
    (
        cd "$REPO"
        git checkout -q -B tmp origin/main
        echo hotfix > hotfix.txt
        git add hotfix.txt
        git -c user.email=t@t -c user.name=T commit -q -m "Hotfix straight onto main"
        git push -q origin HEAD:refs/heads/main
        git fetch -q origin
    )
    run_backmerge --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "Carries file changes"
}

# ── A rejected push is a loud failure ─────────────────────

@test "backmerge: a rejected push fails loudly instead of reporting success" {
    # develop is protected; the push only lands for an identity the ruleset
    # lets through. A rejection must not be mistaken for a back-merge.
    REPO=$(make_repo release)
    local origin
    origin="${REPO%/work}/origin.git"
    mkdir -p "$origin/hooks"
    printf '#!/bin/sh\necho "protected branch" >&2\nexit 1\n' > "$origin/hooks/pre-receive"
    chmod +x "$origin/hooks/pre-receive"

    run_backmerge
    [ "$status" -ne 0 ]
    assert_contains "$output" "rejected"
    assert_not_contains "$output" "Fast-forwarded"
}
