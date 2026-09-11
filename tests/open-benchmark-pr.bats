#!/usr/bin/env bats
#
# Tests for bin/open-benchmark-pr.sh — the standing PR that carries config
# quality score snapshots.
#
# The git half is real: a bare repository stands in for origin, so a push that
# does not happen, or a commit that stages nothing because the scores are
# gitignored, fails here rather than in a workflow nobody reads. Only `gh` is
# stubbed, and it records what it was asked to do.

load helpers/common

# A repo with origin, a develop branch, and the same ignore rule the real one
# has over benchmarks/scores.
make_repo() {
    local dir remote
    remote=$(mktemp -d)
    dir=$(mktemp -d)
    git init -q --bare "$remote/origin.git"
    (
        cd "$dir"
        git init -q -b develop .
        git config user.email t@t
        git config user.name T
        mkdir -p benchmarks/scores config
        printf 'acme = workspace/acme : CLAUDE.md\n' > config/domains.conf
        printf '/benchmarks/scores/*\n' > .gitignore
        git add -A
        git commit -q -m "base"
        git remote add origin "$remote/origin.git"
        git push -q -u origin develop
    )
    printf '%s %s' "$dir" "$remote/origin.git"
}

make_score() {
    local repo="$1" stem="$2" domain="$3" date="$4" total="${5:-20}"
    mkdir -p "$repo/benchmarks/scores"
    cat > "$repo/benchmarks/scores/$stem.json" <<EOF
{"date":"${date}T00:00:00Z","domain":"$domain","git_hash":"x","scores":{"clarity":4,"conciseness":4,"completeness":4,"consistency":4,"actionability":4},"total":$total,"percentage":80,"grade":"B"}
EOF
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
    read -r REPO REMOTE <<< "$(make_repo)"
    BIN=$(mktemp -d)
    make_gh_stub "$BIN"
    export GH_CALLS="$BIN/calls.log"
    export GH_BODY="$BIN/body.md"
    : > "$GH_CALLS"
    : > "$GH_BODY"
}

teardown() {
    # Leave no worktree registered against the fixture before deleting it.
    git -C "$REPO" worktree prune 2>/dev/null || true
    rm -rf "$REPO" "$(dirname "$REMOTE")" "$BIN"
}

publish() {
    run env PATH="$BIN:$PATH" AGENT_CONFIG_ROOT="$REPO" \
        bash -c "cd '$REPO' && '$REPO_ROOT/bin/open-benchmark-pr.sh' $*"
}

remote_branches() {
    git -C "$REMOTE" for-each-ref --format='%(refname:short)' refs/heads
}

@test "open-benchmark-pr: no score records is a clean no-op, not an empty PR" {
    publish
    [ "$status" -eq 0 ]
    assert_contains "$output" "nothing to publish"
    [ ! -s "$GH_CALLS" ]
    assert_not_contains "$(remote_branches)" "benchmark/scores"
}

@test "open-benchmark-pr: publishes the records and opens a PR when none is open" {
    make_score "$REPO" "2026-09-01T120000-acme" acme 2026-09-01
    publish
    [ "$status" -eq 0 ]
    grep -q 'pr create --base develop --head benchmark/scores' "$GH_CALLS"
    ! grep -q 'pr edit' "$GH_CALLS"
    # The record is ON the branch, not merely committed locally.
    run git -C "$REMOTE" show "benchmark/scores:benchmarks/scores/2026-09-01T120000-acme.json"
    [ "$status" -eq 0 ]
    assert_contains "$output" '"domain":"acme"'
}

@test "open-benchmark-pr: score records are force-added past the ignore rule" {
    # benchmarks/scores/* is gitignored, deliberately. Without `git add -f` the
    # staging area stays empty, the script reports success, and the branch
    # carries nothing — a published measurement that does not exist.
    make_score "$REPO" "2026-09-02T120000-acme" acme 2026-09-02
    publish
    [ "$status" -eq 0 ]
    run git -C "$REMOTE" ls-tree --name-only -r "benchmark/scores" -- benchmarks/scores
    [ "$status" -eq 0 ]
    assert_contains "$output" "benchmarks/scores/2026-09-02T120000-acme.json"
}

@test "open-benchmark-pr: refreshes the standing PR instead of opening a second" {
    make_score "$REPO" "2026-09-03T120000-acme" acme 2026-09-03
    GH_EXISTING_PR=77 publish
    [ "$status" -eq 0 ]
    grep -q 'pr edit 77' "$GH_CALLS"
    ! grep -q 'pr create' "$GH_CALLS"
}

@test "open-benchmark-pr: a run with nothing new adds no commit and no noise" {
    make_score "$REPO" "2026-09-04T120000-acme" acme 2026-09-04
    publish
    [ "$status" -eq 0 ]
    local first
    first=$(git -C "$REMOTE" rev-list --count benchmark/scores)
    : > "$GH_CALLS"
    publish
    [ "$status" -eq 0 ]
    assert_contains "$output" "nothing new to publish"
    [ "$(git -C "$REMOTE" rev-list --count benchmark/scores)" -eq "$first" ]
    [ ! -s "$GH_CALLS" ]
}

@test "open-benchmark-pr: the body carries the accumulated trend, not just this run" {
    # The table is read from the branch after the commit, so a refresh shows
    # every measurement the branch holds. Reading it from the local checkout
    # would show only whatever the last eval happened to leave behind.
    make_score "$REPO" "2026-09-05T120000-acme" acme 2026-09-05
    publish
    [ "$status" -eq 0 ]
    rm -f "$REPO/benchmarks/scores/2026-09-05T120000-acme.json"
    make_score "$REPO" "2026-09-06T120000-acme" acme 2026-09-06
    GH_EXISTING_PR=77 publish
    [ "$status" -eq 0 ]
    assert_contains "$(cat "$GH_BODY")" "2026-09-05"
    assert_contains "$(cat "$GH_BODY")" "2026-09-06"
}

@test "open-benchmark-pr: --dry-run prints the body and touches nothing" {
    make_score "$REPO" "2026-09-07T120000-acme" acme 2026-09-07
    publish --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "acme"
    [ ! -s "$GH_CALLS" ]
    assert_not_contains "$(remote_branches)" "benchmark/scores"
}

@test "open-benchmark-pr: leaves no worktree behind" {
    # The commit is built in a temporary detached worktree. One left registered
    # breaks the next run of anything that adds one, including this script.
    make_score "$REPO" "2026-09-08T120000-acme" acme 2026-09-08
    publish
    [ "$status" -eq 0 ]
    run bash -c "git -C '$REPO' worktree list | wc -l"
    [ "$(printf '%s' "$output" | tr -d ' ')" = "1" ]
}

# --- The workflow that drives it ---------------------------------------------
# Wiring, not verdicts. A workflow that stops firing, or that publishes from a
# run that scored nothing, reports green either way.

@test "benchmark workflow: publishing is gated on a run that actually scored" {
    require_python_yaml
    run python3 -c '
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["benchmark"]["steps"]
by_name = {s.get("name"): s for s in steps}
publish = by_name["Publish the snapshots as a standing pull request"]
cond = publish.get("if", "")
# success() because an explicit if replaces the implicit gate, and the skip
# check because publishing after a skipped eval would push a stale set again.
sys.exit(0 if "success()" in cond and "preflight" in cond else 1)
' "$REPO_ROOT/.github/workflows/benchmark.yml"
    [ "$status" -eq 0 ]
}

@test "benchmark workflow: a queued run is never cancelled by a newer one" {
    # Both runs carry scores the other does not. Cancelling the queued one
    # silently drops a measurement, and the report cannot show a gap it was
    # never told about.
    require_python_yaml
    run python3 -c '
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
sys.exit(0 if wf["concurrency"]["cancel-in-progress"] is False else 1)
' "$REPO_ROOT/.github/workflows/benchmark.yml"
    [ "$status" -eq 0 ]
}

@test "benchmark workflow: it can push the branch it publishes to" {
    # contents: write is what the push needs. Without it the job fails at the
    # very last step, after spending a model call per domain.
    require_python_yaml
    run python3 -c '
import sys, yaml
perms = yaml.safe_load(open(sys.argv[1]))["permissions"]
sys.exit(0 if perms.get("contents") == "write" and perms.get("pull-requests") == "write" else 1)
' "$REPO_ROOT/.github/workflows/benchmark.yml"
    [ "$status" -eq 0 ]
}

@test "benchmark workflow: a domain that failed to score still fails the job" {
    # The eval step swallows its own status so the records that succeeded can
    # be published. If nothing carried that failure to the end, a half-measured
    # run would report green.
    require_python_yaml
    run python3 -c '
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["benchmark"]["steps"]
tail = [s for s in steps if "failed" in str(s.get("if", ""))]
sys.exit(0 if tail and "exit 1" in tail[-1].get("run", "") else 1)
' "$REPO_ROOT/.github/workflows/benchmark.yml"
    [ "$status" -eq 0 ]
}
