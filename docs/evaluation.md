# Evaluation

`just eval` scores an AI configuration domain's file stack using Claude itself as the evaluator. It produces structured JSON, validates it against a schema, and accumulates scores so you can see drift over time.

---

## Running

```bash
just eval mobile        # score a single domain
just eval               # score all registered domains
```

Output:
- Per-domain JSON in `evals/results/YYYY-MM-DDTHHMMSS-<domain>.json`
- Compact snapshot in `benchmarks/scores/YYYY-MM-DDTHHMMSS-<domain>.json`
- Findings printed to the terminal

Filenames carry the run timestamp to the second, so a same-day rerun never
overwrites an earlier result. The eval runs on a pinned model by default
(`claude-sonnet-5`) so scores stay comparable; set `EVAL_MODEL` to score with a
different model deliberately.

Both directories are gitignored by default. To save a snapshot to git:

```bash
just benchmark-commit
```

---

## Template Domains

Some registered files ship to be filled in rather than used as they are: the
`user-pers` identity files are prompts, not content. Scored as ordinary config
they are permanently incomplete, and the report carries a domain nobody will
ever fix, which teaches everyone to ignore the number. It sat at a D.

Mark such a domain in the registry, as an optional fourth field:

```
user-pers = user-pers : custom_instructions.md, user_tone_of_voice.md : template
```

The runner passes that through to the evaluator as one line of domain context
(`template: yes`), and the rubric then scores what the file elicits rather than
what it contains: whether every area the filled file needs is prompted for,
whether each prompt says what to write and why, and whether an ordinary reader's
answer would be executable by an agent. An unfilled placeholder stops being a
finding; a prompt that will produce a useless answer becomes one.

The declaration is registry-side on purpose. A file that could declare itself a
template would be able to talk its way out of the rubric, and the eval already
treats everything inside the scored-content markers as data.

Scores before and after the flag are not comparable: the same files moved from
15/25 to 20/25 and 21/25 on two runs. Read the flag as the start of a new
series, not a jump in an old one.

---

## The Scoring Rubric

Five dimensions, each 1 to 5, total 5 to 25. The full prompt lives at
[`evals/prompts/config-quality.md`](../evals/prompts/config-quality.md).

**The scores are not judgements the model makes.** It lists what is wrong, tags
each finding with one dimension and a severity, and the harness computes the
five numbers from that list. A model asked for findings and numbers together
returned numbers its own findings did not support, and nothing downstream could
tell.

| Findings in that dimension | Score |
|---|---|
| two or more major | 1 |
| one major | 2 |
| two or more minor | 3 |
| one minor | 4 |
| none | 5 |

- **major**: an agent following the stack does the wrong thing, has to guess
  about something that changes the outcome, or spends its attention on a whole
  section that carries no instruction.
- **minor**: an agent still lands in the right place, but the file made it
  harder than it needed to be.

Majors dominate deliberately, and an untagged finding counts as major so an
omitted tag cannot flatter a file. At most 3 findings per dimension and 12 in
all, worst first: a global cap alone lets an unlisted dimension keep a 5 it has
not earned.

### What counts as a finding

| Dimension | major | minor |
|---|---|---|
| **Clarity** | a rule an agent cannot execute without guessing | a phrase that is loose but obvious from context |
| **Conciseness** | a section restating rules stated elsewhere, or a passage carrying no instruction | a sentence or two of overlap |
| **Completeness** | an area an agent in this domain will hit, with nothing said about it | an area covered thinly |
| **Consistency** | two rules in the same scope that cannot both be followed | a tension that resolves with context |
| **Actionability** | a rule needing a human: a judgement call with no test, a step naming no command | a rule needing a small inference |

Length alone is not a conciseness finding, and layering is not a consistency
finding: a narrower file overriding a broader one is the design, and so is a
file that states a trade-off and picks a side. Completeness is judged against
the scope a stack sets for itself, so a stack about a repository's workflow or a
person's voice is not marked down for omitting a build command it was never
about.

## Calibration

A rubric can be made stable by making it blind. Narrow what it can express and
every file drifts toward the same comfortable number, which reads as a
stability win right up until nothing fails.

```bash
just calibrate
```

scores the pair this repo already ships, the example config and
[`degraded.md`](../evals/examples/degraded.md), and fails unless the good one
still scores 20 or better, the rotted one 16 or worse, and the gap is at least
6 points. Two model calls, so it is not in CI; run it whenever the rubric or the
scoring code changes and put the numbers in the pull request.

The arithmetic half of the same question does run in CI:
`tests/scoring-derivation.bats` feeds synthetic findings to the deduction rule,
including the shape `degraded.md` produces.

## Rubric versions

Every result and score record carries `rubric_version`, stamped by the harness
rather than asked of the model, and `just benchmark` shows it as a column.

| Version | Rubric |
|---|---|
| 1 | five gestalt judgements, anchored only at 5, 3 and 1 (still used by `skill-quality.md`) |
| 2 | findings first, tagged major or minor, scores derived from them |

The version belongs to the prompt, so each runner sets it: `evals/run-eval.sh`
declares 2, and `evals/run-skill-eval.sh` leaves the default of 1 because its
rubric has not changed. Scores from different versions are different
measurements in the same units, so compare within a version and read a jump at
a boundary as the boundary.

## Grade Mapping

- 23–25 → **A**
- 20–22 → **B**
- 17–19 → **C**
- 14–16 → **D**
- below 14 → **F**

---

## Reading the Output

Example `evals/results/2026-05-25T103000-mobile.json`:

```json
{
  "date": "2026-05-25T10:30:00Z",
  "domain": "mobile",
  "git_hash": "1477b4c",
  "rubric_version": 2,
  "scores": {
    "clarity": 5,
    "conciseness": 4,
    "completeness": 5,
    "consistency": 5,
    "actionability": 5
  },
  "total": 24,
  "percentage": 96,
  "grade": "A",
  "findings": [
    {
      "dimension": "conciseness",
      "severity": "minor",
      "file": "AGENTS.md",
      "section": "Build & Gradle",
      "issue": "Command table restates commands already listed inline above it",
      "recommendation": "Remove the table; keep inline references only."
    }
  ]
}
```

One minor conciseness finding, so conciseness scores 4 and everything else
scores 5. The numbers follow the list; they are not a separate opinion.

Read the findings as actionable PR items. After fixing them, re-run `just eval` and watch the score move up.

---

## Trend Reports

```bash
just benchmark
```

Prints one table per domain:

```
mobile
──────────────────────────────────────────────────────────────────
Date         Clarity   Concise   Complete   Consistent   Action    Total  Grade
2026-05-10   4         3         5          4            4         80%    B
2026-05-25   4         4         5          4            4         84%    B+
```

If a score drops, look at the most recent `evals/results/` entry to see why.

A table with one row in it is not a trend, which is what this looked like for
months: scores are gitignored, so a run that scored the domains and stopped
left nothing behind, and the report showed whichever afternoon somebody last
ran `just eval` by hand.

[`.github/workflows/benchmark.yml`](../.github/workflows/benchmark.yml) closes
that. It scores every registered domain when the config it measures changes on
`develop` (with a Monday cron as a net, because a push is reliable and a
schedule is not), then runs:

```bash
just benchmark-pr           # commit the records, push, open or refresh the PR
just benchmark-pr-preview   # print the body, touch nothing
```

The records land on a standing `benchmark/scores` branch behind one pull
request that is refreshed rather than reopened, so the churn is a single PR
rather than one per run. It never merges: keeping a measurement in the
repository's history is a human decision, the same as a release.

Two things worth knowing about it:

- **It needs the same `ANTHROPIC_API_KEY` secret** the CI action does, and
  skips loudly without one.
- **It publishes as a person, using `RELEASE_PR_TOKEN`.** A pull request GitHub
  attributes to Actions raises no `pull_request` runs at all, and this repo
  requires two, so such a pull request is permanently unmergeable while looking
  merely pending. The token needs Contents: write as well as Pull requests:
  write, and the job checks for it before spending a model call per domain.
- **The branch is rebuilt from `develop` every run**, carrying forward whatever
  the open pull request still holds. Grown from itself it kept every record it
  had ever carried, because the base merges it by squash and the branch never
  becomes an ancestor.

---

## In CI

The same rubric runs as a [GitHub Action](../action.yml), and this repository
runs it on itself:
[`.github/workflows/config-eval.yml`](../.github/workflows/config-eval.yml)
scores the repo's own `CLAUDE.md`.

It triggers on a change to the scored file or to any part of the action that
scores it (the rubric prompt, `bin/eval-action.sh`, `evals/run-eval.sh`,
`lib/scoring.sh`), and on `workflow_dispatch`. Every bats test of the action
stubs the Claude CLI, so this workflow is the only place the install step, the
live model call and the job-summary rendering run for real.

It does that in two jobs, and which one runs is a trust decision:

| Job | Fires on | Runs |
|---|---|---|
| `gate` | a pull request | the **released** action, pinned by commit |
| `dogfood` | a push to `develop`, or a dispatch | `uses: ./`, the tree as merged |

`uses: ./` executes the checked-out tree. A pull request can change that tree,
so running it with `ANTHROPIC_API_KEY` in the environment would hand the secret
to code the pull request author wrote. A fork never sees repository secrets, but
a branch pushed to the repository itself does. So a pull request is scored by
trusted code that reads its `CLAUDE.md` as data, and the tree is executed only
once it has been merged, which is still before any release can carry it.

Three more things about it are deliberate:

- **It needs an `ANTHROPIC_API_KEY` repository secret.** Without one the job
  skips and says so in the job summary, in those words: the check is green
  because nothing failed, not because anything passed. A pull request from a
  fork never sees repository secrets, so that state is normal there.
- **It is path-filtered, so it must never be a required status check.** GitHub
  holds a required check that never runs as pending forever, which would block
  every pull request outside those paths.
- **The two path filters are written out twice**, once per event, because
  GitHub's workflow parser does not support YAML anchors. A test keeps them
  identical; drift would mean the tree is proven on a narrower set of changes
  than the gate runs on.

The threshold is `fail-below: C`. Scoring moves by 1 to 2 points on borderline
cases, so a tighter gate fails pull requests for non-determinism and trains
everyone to re-run until green.

---

## Caveats

- **AI scoring is non-deterministic**, and a rerun over an unchanged tree can
  move the total by enough to change the grade. Deriving the scores from tagged
  findings narrows that and does not remove it. Read a one-point move as noise,
  and prefer the findings to the total, which are the more stable half of the
  output.
- **Stability is not the only thing to measure.** A rubric that cannot express a
  bad config is perfectly stable. `just calibrate` is the check that asks the
  other half of the question, and a rubric change is not finished until it has
  passed.
- **A stack the rubric cannot place is the least stable of all.** A file about a
  repository's own workflow is not a language and a build, and scoring it as
  though it were makes the model pick a framing rather than measure a file. If a
  score swings hard, suspect the question before the file.
- The model interpretation depends on the prompt. If a score feels wrong, the fix is usually in [`evals/prompts/config-quality.md`](../evals/prompts/config-quality.md), not the file under test.
- Schema validation (via `ajv-cli`) is optional. Without it, malformed output is detected by `jq` parse but not field-level checked.
