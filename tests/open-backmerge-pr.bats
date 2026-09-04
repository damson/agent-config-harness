#!/usr/bin/env bats
#
# Tests for bin/open-backmerge-pr.sh — the main → develop PR after a release.
#
# Same harness as open-release-pr.bats: the real script against a throwaway
# repo, with `gh` stubbed onto PATH so calls are recorded instead of sent.

load helpers/common

# A repo where origin/main is $behind commits ahead of origin/develop, in the
# shape a release leaves behind: merge commits on main, identical trees.
make_repo() {
    local behind="$1" with_content="${2:-0}" dir
    dir=$(mktemp -d)
    (
        cd "$dir"
        git init -q .
        git config user.email t@t
        git config user.name T
        git commit -q --allow-empty -m "base"
        git update-ref refs/remotes/origin/develop HEAD
        if [ "$behind" -gt 0 ]; then
            if [ "$with_content" -eq 1 ]; then
                # A hotfix straight onto main: the trees genuinely differ.
                echo hotfix > hotfix.txt
                git add hotfix.txt
                git commit -q -m "Hotfix applied directly to main"
            else
                # A release merge: no file changes, one commit of history.
                git commit -q --allow-empty -m "Merge pull request #66 from owner/develop"
            fi
        fi
        git update-ref refs/remotes/origin/main HEAD
    )
    printf '%s' "$dir"
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
    REPO=$(make_repo 1)
    BIN=$(mktemp -d)
    make_gh_stub "$BIN"
    export GH_CALLS="$BIN/calls.log"
    : > "$GH_CALLS"
}

teardown() {
    rm -rf "$REPO" "$BIN"
}

@test "open-backmerge-pr: does nothing when develop is already level" {
    local repo
    repo=$(make_repo 0)
    run env PATH="$BIN:$PATH" bash -c "cd '$repo' && '$REPO_ROOT/bin/open-backmerge-pr.sh'"
    [ "$status" -eq 0 ]
    assert_contains "$output" "nothing to back-merge"
    [ ! -s "$GH_CALLS" ]
    rm -rf "$repo"
}

@test "open-backmerge-pr: opens a PR from main into develop, not the reverse" {
    run env PATH="$BIN:$PATH" GH_EXISTING_PR="" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-backmerge-pr.sh'"
    [ "$status" -eq 0 ]
    # Direction is the whole point: base develop, head main. Reversed, this
    # would open a second release PR and promote unreviewed work.
    grep -q 'pr create --base develop --head main' "$GH_CALLS"
    ! grep -q 'pr edit' "$GH_CALLS"
}

@test "open-backmerge-pr: refreshes the open PR instead of opening a second one" {
    run env PATH="$BIN:$PATH" GH_EXISTING_PR="77" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-backmerge-pr.sh'"
    [ "$status" -eq 0 ]
    grep -q 'pr edit 77' "$GH_CALLS"
    ! grep -q 'pr create' "$GH_CALLS"
}

@test "open-backmerge-pr: a routine back-merge is reported as history-only" {
    run env PATH="$BIN:$PATH" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-backmerge-pr.sh' --dry-run"
    [ "$status" -eq 0 ]
    assert_contains "$output" "History only"
    assert_contains "$output" "#66"
}

@test "open-backmerge-pr: a hotfix on main is reported as carrying file changes" {
    local repo
    repo=$(make_repo 1 1)
    run env PATH="$BIN:$PATH" bash -c "cd '$repo' && '$REPO_ROOT/bin/open-backmerge-pr.sh' --dry-run"
    [ "$status" -eq 0 ]
    # Silently calling this "history only" is the failure that matters: it
    # invites a rubber-stamp merge of an unreviewed change.
    assert_contains "$output" "Carries file changes"
    assert_not_contains "$output" "History only"
    rm -rf "$repo"
}

@test "open-backmerge-pr: --dry-run touches nothing" {
    run env PATH="$BIN:$PATH" bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-backmerge-pr.sh' --dry-run"
    [ "$status" -eq 0 ]
    [ ! -s "$GH_CALLS" ]
}

@test "back-merge: the review-skip keyword matches the title the script generates" {
    # The keyword and the title live in two files that no build step relates.
    # Rename the PR title and CodeRabbit silently starts reviewing back-merges
    # again; nothing goes red, the noise just comes back.
    require_python_yaml
    local title keyword
    # Render the script's own title format with its documented defaults.
    title=$(grep -oE -- '--title "[^"]+"' "$REPO_ROOT/bin/open-backmerge-pr.sh" \
        | head -1 | sed -E 's/--title "(.*)"/\1/; s/\$HEAD/main/; s/\$BASE/develop/')
    [ -n "$title" ]
    keyword=$(python3 -c '
import sys, yaml
kws = yaml.safe_load(open(sys.argv[1]))["reviews"]["auto_review"]["ignore_title_keywords"]
print(kws[0])
' "$REPO_ROOT/.coderabbit.yaml")
    [ -n "$keyword" ]
    case "$title" in
        *"$keyword"*) : ;;
        *) printf 'title %s does not contain the skip keyword %s\n' "$title" "$keyword" >&2; return 1 ;;
    esac
}
