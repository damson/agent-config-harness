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
