#!/usr/bin/env bats
#
# Tests for .github/workflows/config-eval.yml — the workflow that scores this
# repo's own CLAUDE.md with this repo's own config-scoring action.
#
# Nothing here calls the API. What these guard is the wiring, which is the part
# that fails silently: a workflow that stops firing, one that scores a released
# tag when it meant to prove the current tree, and one that hands an API key to
# code a pull request author wrote. All three still report green.

load helpers/common

WF() { printf '%s' "$REPO_ROOT/.github/workflows/config-eval.yml"; }

@test "config-eval workflow: fires on a change to the scored file and to the machinery that scores it" {
    # The dogfood is worth having only when it runs on the changes that can
    # break it. Move the rubric prompt or the action entry point out of this
    # list and the workflow keeps passing while it has stopped watching the
    # thing that changed.
    require_python_yaml
    run python3 -c '
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
on = wf[True]   # PyYAML reads `on:` as True
need = {"CLAUDE.md", "action.yml", "bin/eval-action.sh", "evals/run-eval.sh",
        "evals/prompts/config-quality.md", "lib/scoring.sh"}
missing = need - set(on["pull_request"]["paths"])
if missing:
    print("paths filter is missing:", sorted(missing)); sys.exit(1)
# The two lists are written out twice because GitHub rejects YAML anchors. They
# have to stay identical, or the tree is proven on a narrower set of changes
# than the gate runs on.
if on["pull_request"]["paths"] != on["push"]["paths"]:
    print("pull_request and push path filters have drifted apart"); sys.exit(1)
' "$(WF)"
    [ "$status" -eq 0 ]
}

@test "config-eval workflow: a pull request never executes the tree it is scoring" {
    # `uses: ./` runs the checked-out tree, and a pull request can change that
    # tree. With ANTHROPIC_API_KEY in the environment, that hands the secret to
    # code the pull request author wrote. Forks get no secrets; a branch pushed
    # to this repository does. So the pull-request job must run a pinned
    # external ref, and the local action must be gated away from pull requests.
    require_python_yaml
    run python3 -c '
import sys, yaml
jobs = yaml.safe_load(open(sys.argv[1]))["jobs"]
bad = []
for name, job in jobs.items():
    cond = str(job.get("if", ""))
    runs_local = any(s.get("uses") == "./" for s in job["steps"])
    takes_key = any("ANTHROPIC_API_KEY" in str(s.get("env", {})) for s in job["steps"])
    if runs_local and takes_key and "event_name != " not in cond:
        bad.append(name)
    for s in job["steps"]:
        ref = s.get("uses", "")
        if ref.startswith("damson/agent-config-harness@") and len(ref.split("@")[1]) != 40:
            bad.append(name + " (unpinned action ref)")
if bad:
    print("jobs that expose the key to pull-request code:", bad); sys.exit(1)
' "$(WF)"
    [ "$status" -eq 0 ]
}

@test "config-eval workflow: the merged tree is still proven end to end" {
    # The reason the workflow exists. Every bats test of the action stubs the
    # Claude CLI; if nothing ever runs `uses: ./` with a key, the install step
    # and the live call are proven by reading them and nothing else.
    require_python_yaml
    run python3 -c '
import sys, yaml
jobs = yaml.safe_load(open(sys.argv[1]))["jobs"]
for job in jobs.values():
    for s in job["steps"]:
        if s.get("uses") == "./" and "ANTHROPIC_API_KEY" in str(s.get("env", {})):
            sys.exit(0)
print("no job scores with the action as this tree defines it"); sys.exit(1)
' "$(WF)"
    [ "$status" -eq 0 ]
}

@test "config-eval workflow: every scoring step still respects an earlier failure" {
    # An explicit `if:` REPLACES the implicit success() gate. Without success()
    # in the condition, a failed checkout is followed by a scoring step that
    # runs anyway, against whatever is (or is not) on disk.
    require_python_yaml
    run python3 -c '
import sys, yaml
jobs = yaml.safe_load(open(sys.argv[1]))["jobs"]
steps = [s for job in jobs.values() for s in job["steps"]
         if "ANTHROPIC_API_KEY" in str(s.get("env", {})) and s.get("uses")]
if not steps:
    print("no scoring step found"); sys.exit(1)
bad = [s["name"] for s in steps if "success()" not in s.get("if", "")]
if bad:
    print("scoring steps with no success() gate:", bad); sys.exit(1)
' "$(WF)"
    [ "$status" -eq 0 ]
}

@test "config-eval workflow: a run that cannot score says so where the grade would be" {
    # Skipping on a missing key is deliberate, and it reports green. The only
    # thing separating that from a real pass is the sentence in the job
    # summary, so it is load-bearing and tested like it. Both jobs carry it.
    [ "$(grep -c 'Config eval: NOT RUN' "$(WF)")" -eq 2 ]
    [ "$(grep -c 'green because nothing failed, not because anything passed' "$(WF)")" -eq 2 ]
}
