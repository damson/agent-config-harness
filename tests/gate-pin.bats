#!/usr/bin/env bats
#
# Tests for bin/bump-gate-pin.sh and the workflow that runs it: the thing that
# keeps the pull-request gate scoring with the release this repo actually ships.
#
# No release is read from the network. The script takes the commit and tag as
# env when it is given them, which is the seam these use.

load helpers/common

setup() {
    cd "$REPO_ROOT"
    WORK=$(mktemp -d)
    # A workflow shaped like the real one, pinned to $OLD.
    OLD="1111111111111111111111111111111111111111"
    NEW="2222222222222222222222222222222222222222"
    printf 'jobs:\n  gate:\n    steps:\n      - name: Score\n        uses: damson/agent-config-harness@%s # v1.0.0\n' \
        "$OLD" > "$WORK/config-eval.yml"
}

teardown() {
    rm -rf "$WORK"
}

bump() {
    run env GATE_WORKFLOW="$WORK/config-eval.yml" GITHUB_OUTPUT="$WORK/out" "$@" \
        ./bin/bump-gate-pin.sh
}

@test "gate pin: a release the gate already runs is a quiet no-op" {
    bump GATE_REF="$OLD" GATE_TAG=v1.0.0
    [ "$status" -eq 0 ]
    assert_contains "$output" "Nothing to do"
    grep -q "changed=false" "$WORK/out"
    grep -q "agent-config-harness@$OLD # v1.0.0" "$WORK/config-eval.yml"
}

@test "gate pin: a new release rewrites the pin and the tag beside it" {
    # The comment is not decoration: it is how a reader knows which release a
    # 40-character string is, and a stale one is worse than none.
    bump GATE_REF="$NEW" GATE_TAG=v1.5.0
    [ "$status" -eq 0 ]
    grep -q "agent-config-harness@$NEW # v1.5.0" "$WORK/config-eval.yml"
    assert_not_contains "$(cat "$WORK/config-eval.yml")" "$OLD"
    grep -q "changed=true" "$WORK/out"
    grep -q "tag=v1.5.0" "$WORK/out"
}

@test "gate pin: --dry-run says what would move and touches nothing" {
    run env GATE_WORKFLOW="$WORK/config-eval.yml" GATE_REF="$NEW" GATE_TAG=v1.5.0 \
        ./bin/bump-gate-pin.sh --dry-run
    [ "$status" -eq 0 ]
    assert_contains "$output" "Gate pin moves"
    grep -q "agent-config-harness@$OLD" "$WORK/config-eval.yml"
}

@test "gate pin: anything that is not a full commit sha is refused" {
    # A tag here would keep the shape and lose the guarantee: the gate exists to
    # run code a pull request cannot edit, and a mutable ref is code it can.
    bump GATE_REF=v1.5.0 GATE_TAG=v1.5.0
    [ "$status" -ne 0 ]
    assert_contains "$output" "not a full commit sha"
    grep -q "agent-config-harness@$OLD" "$WORK/config-eval.yml"
}

@test "gate pin: a workflow with no pin is an error, not a silent success" {
    printf 'jobs:\n  gate:\n    steps:\n      - uses: ./\n' > "$WORK/config-eval.yml"
    bump GATE_REF="$NEW" GATE_TAG=v1.5.0
    [ "$status" -ne 0 ]
    assert_contains "$output" "No pinned commit found"
}

@test "gate-pin workflow: fires on the promotion, not only on the tag" {
    # A push to main is the first moment the released commit exists. Waiting for
    # `release: published` alone would tie this to a hand-tagging step that can
    # be skipped or delayed.
    require_python_yaml
    run python3 -c '
import sys, yaml
on = yaml.safe_load(open(sys.argv[1]))[True]
missing = [e for e in ("push", "release", "workflow_dispatch") if e not in on]
if missing:
    print("missing triggers:", missing); sys.exit(1)
if on["push"]["branches"] != ["main"]:
    print("push trigger is not main:", on["push"]); sys.exit(1)
' "$REPO_ROOT/.github/workflows/gate-pin.yml"
    [ "$status" -eq 0 ]
}

@test "gate-pin workflow: opens as a person, lands on develop, and is gated on a real change" {
    require_python_yaml
    run python3 -c '
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["bump"]["steps"]
named = {s.get("name"): s for s in steps}
checkout = [s for s in steps if str(s.get("uses","")).startswith("actions/checkout")][0]
bad = []
if "RELEASE_PR_TOKEN" not in str(checkout.get("with", {})):
    bad.append("checkout pushes with the default token")
if checkout["with"].get("ref") != "develop":
    bad.append("checkout is not on develop, so the bump would land on main")
if "RELEASE_PR_TOKEN" not in str(named["Open or refresh the pull request"].get("env", {})):
    bad.append("the PR is opened with the default token")
for n in ("Run the suite against the rewritten workflow", "Open or refresh the pull request"):
    cond = str(named[n].get("if", ""))
    if "changed" not in cond or "success()" not in cond:
        bad.append(n + " is not gated on success() and a real change")
if bad:
    print("; ".join(bad)); sys.exit(1)
' "$REPO_ROOT/.github/workflows/gate-pin.yml"
    [ "$status" -eq 0 ]
}

# The preflight's job is to answer "can this token do what the push needs",
# which an emptiness check cannot. These run its real script against a stub
# `gh`, because a step that only parses is a step nobody has run.
preflight_script() {
    require_python_yaml
    python3 -c '
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["bump"]["steps"]
for s in steps:
    if "token can do" in s.get("name", ""):
        sys.stdout.write(s["run"]); break
else:
    sys.exit("preflight step not found by name")
' "$REPO_ROOT/.github/workflows/gate-pin.yml" > "$WORK/preflight.sh"
}

# $1 = login or empty to fail auth, $2 = permissions.push, $3 = X-OAuth-Scopes
stub_gh() {
    mkdir -p "$WORK/bin"
    printf '%s\n' "$1" > "$WORK/login"
    printf '%s\n' "$2" > "$WORK/push"
    printf '%s\n' "$3" > "$WORK/scopes"
    cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
d=$(dirname "$0")/..
login=$(cat "$d/login"); push=$(cat "$d/push"); scopes=$(cat "$d/scopes")
case "$*" in
    *"-i user"*)  [ -n "$scopes" ] && printf 'X-OAuth-Scopes: %s\r\n' "$scopes"; exit 0 ;;
    *"api user"*) [ -n "$login" ] || { echo "HTTP 401: Bad credentials" >&2; exit 1; }
                  printf '%s\n' "$login"; exit 0 ;;
    *permissions*) printf '%s\n' "$push"; exit 0 ;;
esac
exit 0
EOF
    chmod +x "$WORK/bin/gh"
}

run_preflight() {
    run env PATH="$WORK/bin:$PATH" GITHUB_REPOSITORY=damson/agent-config-harness \
        GH_TOKEN="$1" bash "$WORK/preflight.sh"
}

@test "gate-pin preflight: a missing token names every permission it needs" {
    preflight_script
    stub_gh "" "" ""
    run_preflight ""
    [ "$status" -ne 0 ]
    assert_contains "$output" "Contents: read and write"
    assert_contains "$output" "Pull requests: read and write"
    # The one the old message left out, and the one the push actually dies on.
    assert_contains "$output" "Workflows: read and write"
}

@test "gate-pin preflight: a token that does not authenticate says so" {
    preflight_script
    stub_gh "" "" ""
    run_preflight "dead-token"
    [ "$status" -ne 0 ]
    assert_contains "$output" "does not authenticate"
}

@test "gate-pin preflight: a read-only token is refused before the suite runs" {
    preflight_script
    stub_gh "damson" "false" ""
    run_preflight "read-only-token"
    [ "$status" -ne 0 ]
    assert_contains "$output" "no write access"
    assert_contains "$output" "Contents: read and write"
}

@test "gate-pin preflight: a classic token without the workflow scope is refused" {
    preflight_script
    stub_gh "damson" "true" "repo, read:org"
    run_preflight "classic-token"
    [ "$status" -ne 0 ]
    assert_contains "$output" "workflow"
}

@test "gate-pin preflight: the scope list is matched whatever case it arrives in" {
    # Rejecting a valid token because a header arrived capitalised is the worst
    # shape of failure here: it blocks the release bump and blames the token.
    preflight_script
    stub_gh "damson" "true" "Repo, WORKFLOW"
    run_preflight "classic-token-shouting"
    [ "$status" -eq 0 ]
    assert_contains "$output" "authenticates as damson"
}

@test "gate-pin preflight: a scope carrying its own colon does not confuse the parse" {
    # `read:org` has a colon in it, so splitting the header on every colon
    # truncates the list and loses the scope that matters.
    preflight_script
    stub_gh "damson" "true" "repo, read:org, workflow"
    run_preflight "classic-token-with-colons"
    [ "$status" -eq 0 ]
}

@test "gate-pin preflight: a token that can do the job passes" {
    preflight_script
    stub_gh "damson" "true" "repo, workflow"
    run_preflight "good-token"
    [ "$status" -eq 0 ]
    assert_contains "$output" "authenticates as damson"
}

@test "gate-pin preflight: a fine-grained token passes, since its scopes cannot be read" {
    # No X-OAuth-Scopes header at all. Workflows is not introspectable here, so
    # the preflight must not invent a verdict; the push step names it instead.
    preflight_script
    stub_gh "damson" "true" ""
    run_preflight "fine-grained-token"
    [ "$status" -eq 0 ]
}

@test "gate-pin workflow: the push reports which permission a bare 403 means" {
    require_python_yaml
    run python3 -c '
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["bump"]["steps"]
step = [s for s in steps if s.get("name") == "Open or refresh the pull request"][0]
run = step["run"]
bad = []
if "git push" in run and "push_output" not in run:
    bad.append("the push failure is not captured")
if "Workflows: read and write" not in run:
    bad.append("the push failure does not name the Workflows permission")
if bad:
    print("; ".join(bad)); sys.exit(1)
' "$REPO_ROOT/.github/workflows/gate-pin.yml"
    [ "$status" -eq 0 ]
}

# The push to main resolves the release that tags the promoted commit, not the
# newest release, which at that moment is the one BEFORE it. Routing the push
# through "latest" made the trigger compare the pin against a release it
# already ran and report success having done nothing, on every release.
stub_gh_tags() {
    # $1 = tag pointing at the commit, or empty for none. $2 = that tag's sha.
    mkdir -p "$WORK/bin"
    printf '%s\n' "$1" > "$WORK/tagname"
    printf '%s\n' "$2" > "$WORK/tagsha"
    cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
d=$(dirname "$0")/..
case "$*" in
    *"repo view"*)  printf 'damson/agent-config-harness\n' ;;
    *"/tags"*)      t=$(cat "$d/tagname"); [ -n "$t" ] && printf '%s\n' "$t" ;;
    *"/commits/"*)  cat "$d/tagsha" ;;
esac
exit 0
EOF
    chmod +x "$WORK/bin/gh"
}

bump_for_commit() {
    run env PATH="$WORK/bin:$PATH" GATE_WORKFLOW="$WORK/config-eval.yml" \
        GITHUB_OUTPUT="$WORK/out" GATE_FOR_COMMIT="$1" ./bin/bump-gate-pin.sh
}

@test "gate pin: a promotion nothing has tagged yet is not reported as current" {
    stub_gh_tags "" ""
    bump_for_commit "$NEW"
    [ "$status" -eq 0 ]
    # The distinction that matters: not due yet, rather than already done.
    assert_contains "$output" "Nothing tags $NEW yet"
    assert_not_contains "$output" "already runs"
    grep -q 'changed=false' "$WORK/out"
    # And the pin is untouched, since there was nothing to move it to.
    grep -q "agent-config-harness@$OLD" "$WORK/config-eval.yml"
}

@test "gate pin: a promotion that is already tagged bumps to that release" {
    stub_gh_tags "v9.9.9" "$NEW"
    bump_for_commit "$NEW"
    [ "$status" -eq 0 ]
    assert_contains "$output" "v9.9.9"
    grep -q 'changed=true' "$WORK/out"
    grep -q "agent-config-harness@$NEW # v9.9.9" "$WORK/config-eval.yml"
}

@test "gate pin: a commit that is already the pin stays a quiet no-op" {
    # The honest "nothing to do", kept distinct from the one above.
    stub_gh_tags "v1.0.0" "$OLD"
    bump_for_commit "$OLD"
    [ "$status" -eq 0 ]
    assert_contains "$output" "already runs"
    grep -q 'changed=false' "$WORK/out"
}

@test "gate-pin workflow: each trigger resolves the release it knows about" {
    require_python_yaml
    run python3 -c '
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["bump"]["steps"]
step = [s for s in steps if s.get("id") == "bump"][0]
env = step.get("env", {})
bad = []
if "GATE_FOR_COMMIT" not in env:
    bad.append("the push does not pass the promoted commit")
elif "push" not in env["GATE_FOR_COMMIT"] or "github.sha" not in env["GATE_FOR_COMMIT"]:
    bad.append("GATE_FOR_COMMIT is not the pushed commit, gated on the push event")
if "GATE_TAG" not in env:
    bad.append("the release event does not pass its own tag")
elif "release" not in env["GATE_TAG"]:
    bad.append("GATE_TAG is not gated on the release event")
if bad:
    print("; ".join(bad)); sys.exit(1)
' "$REPO_ROOT/.github/workflows/gate-pin.yml"
    [ "$status" -eq 0 ]
}
