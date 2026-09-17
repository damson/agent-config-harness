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

**The scores are not judgements the model makes directly.** It lists findings
first, tags each with one dimension and a severity, and the score for a
dimension follows from what it listed:

| Findings in that dimension | Score |
|---|---|
| none | 5 |
| one minor | 4 |
| two or more minor, or one major | 3 |
| one major and any minor, or two major | 2 |
| three or more major | 1 |

- **major**: an agent following the stack does the wrong thing, or has to guess
  about something that changes the outcome.
- **minor**: an agent still lands in the right place, but the file made it
  harder than it needed to be.

The order matters more than the table. Asked for five numbers directly, the
model produced a different set each run over an unchanged file; asked for
findings, it produced nearly the same list each time and the numbers now follow
that list. The measured effect is under "Caveats".

### What counts as a finding

| Dimension | A finding is |
|---|---|
| **Clarity** | a rule an agent could read two ways, or that leaves it guessing about something that matters |
| **Conciseness** | material restated elsewhere, a summary that repeats rules, a passage carrying no instruction. Length alone is not a finding |
| **Completeness** | an area an agent in this domain will hit that the stack says nothing about: conventions, architecture, testing, git, build |
| **Consistency** | two rules in the same scope that cannot both be followed. Deliberate layering is not a contradiction, and neither is stating a trade-off and picking a side |
| **Actionability** | a rule whose execution needs a human: a judgement call with no test, "use discretion", a step naming no command or condition |

A finding belongs to exactly one dimension, so one problem is one deduction. An
excellent stack produces no findings and scores 25.

## Rubric versions

Every result and score record carries `rubric_version`, stamped by the harness
rather than asked of the model, and `just benchmark` shows it as a column.

| Version | Rubric |
|---|---|
| 1 | five gestalt judgements, anchored only at 5, 3 and 1 |
| 2 | findings first, tagged major or minor, scores derived from them |

Scores from different rubric versions are different measurements in the same
units. Compare within a version, and read a jump at a version boundary as the
boundary, not as the config changing. Bump `RUBRIC_VERSION` in
[`lib/scoring.sh`](../lib/scoring.sh) whenever a prompt change moves what the
numbers mean.

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
  "scores": {
    "clarity": 4,
    "conciseness": 3,
    "completeness": 5,
    "consistency": 4,
    "actionability": 4
  },
  "total": 20,
  "percentage": 80,
  "grade": "B",
  "findings": [
    {
      "dimension": "conciseness",
      "file": "AGENTS.md",
      "section": "Build & Gradle",
      "issue": "Command table restates commands already listed inline above it",
      "recommendation": "Remove the table; keep inline references only."
    }
  ]
}
```

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
- **That pull request arrives with no checks**, because a pull request opened
  with `GITHUB_TOKEN` does not get them and the review bot skips bot authors.
  Acceptable for machine-written JSON whose only decision is keep or discard,
  and not acceptable for a change to the harness itself.

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

- **AI scoring is non-deterministic, and rubric 2 exists because of how much.**
  Measured over identical trees on 2026-09-17, four runs per domain for rubric 2
  and three for rubric 1:

  | Domain | Rubric 1 | Rubric 2 |
  |---|---|---|
  | `mobile` | 21, 24, 21 (B, A, B) | 22, 20, 20, 21 (B, B, B, B) |
  | `user-pers` | 21, 24, 24 (B, A, A) | 23, 23, 23, 23 (A, A, A, A) |

  Rubric 1 crossed the A/B boundary on both domains without a file changing,
  which is the failure that matters: a grade nobody can reproduce. Deriving the
  scores from tagged findings narrowed the spread to 2 points and 0, and the
  grade held across every run.
- **It is narrower, not gone.** `mobile` still moves by 2. Do not read a
  1-point move as a result, and prefer the findings to the total: they were the
  stable half even under rubric 1, which is why the scores are now computed from
  them.
- The model interpretation depends on the prompt. If a score feels wrong, the fix is usually in [`evals/prompts/config-quality.md`](../evals/prompts/config-quality.md), not the file under test.
- Schema validation (via `ajv-cli`) is optional. Without it, malformed output is detected by `jq` parse but not field-level checked.
