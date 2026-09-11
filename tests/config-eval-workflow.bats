#!/usr/bin/env bats
#
# Tests for .github/workflows/config-eval.yml — the workflow that runs this
# repo's own config-scoring action against this repo's own CLAUDE.md.
#
# Nothing here calls the API. What these guard is the wiring, which is the part
# that fails silently: a workflow that stops firing, or that scores a released
# tag instead of the change in front of it, still reports green.

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
paths = set(wf[True]["pull_request"]["paths"])   # PyYAML reads `on:` as True
need = {"CLAUDE.md", "action.yml", "bin/eval-action.sh", "evals/run-eval.sh",
        "evals/prompts/config-quality.md", "lib/scoring.sh"}
missing = need - paths
if missing:
    print("paths filter is missing:", sorted(missing))
    sys.exit(1)
' "$(WF)"
    [ "$status" -eq 0 ]
}

@test "config-eval workflow: scores with the action as this pull request changes it" {
    # `uses: ./` is the whole point: a released tag would score the pull
    # request with the action from BEFORE the pull request, so a broken rubric
    # or a broken install step would pass here and fail at a consumer.
    require_python_yaml
    run python3 -c '
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["score"]["steps"]
uses = [s.get("uses") for s in steps if "eval" in str(s.get("with", {})).lower() or s.get("uses") == "./"]
sys.exit(0 if "./" in uses else 1)
' "$(WF)"
    [ "$status" -eq 0 ]
}

@test "config-eval workflow: the scoring step still respects an earlier failure" {
    # An explicit `if:` REPLACES the implicit success() gate. Without success()
    # in the condition, a failed checkout is followed by a scoring step that
    # runs anyway, against whatever is (or is not) on disk.
    require_python_yaml
    run python3 -c '
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["score"]["steps"]
score = [s for s in steps if s.get("uses") == "./"]
if not score:
    print("no step runs the local action"); sys.exit(1)
cond = score[0].get("if", "")
sys.exit(0 if "success()" in cond else 1)
' "$(WF)"
    [ "$status" -eq 0 ]
}

@test "config-eval workflow: a run that cannot score says so where the grade would be" {
    # Skipping on a missing key is deliberate, and it reports green. The only
    # thing separating that from a real pass is the sentence in the job
    # summary, so it is load-bearing and tested like it.
    grep -q 'Config eval: NOT RUN' "$(WF)"
    grep -q 'green because nothing failed, not because anything passed' "$(WF)"
}
