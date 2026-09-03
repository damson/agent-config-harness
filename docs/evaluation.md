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

## The Scoring Rubric

Five dimensions, each 1–5. Total 5–25. The full prompt lives at [`evals/prompts/config-quality.md`](../evals/prompts/config-quality.md).

### 1. Clarity

**Are rules specific and unambiguous?** An agent should not have to guess.

| Score | Description |
|---|---|
| **5** | Every rule is precise. No interpretation needed. |
| **4** | Mostly specific with the occasional vague line. |
| **3** | Many rules are clear; some require judgment. |
| **2** | Several rules are abstract. |
| **1** | Mostly vague. "Follow best practices." |

### 2. Conciseness

**Free of bloat, summary sections, and restated material?**

| Score | Description |
|---|---|
| **5** | Lean. Every line earns its place. |
| **3** | Some redundancy. |
| **1** | Heavy duplication. Reminder sections that repeat rules. |

### 3. Completeness

**Does it cover the essential areas for this domain?**

For a typical domain, "essential areas" include: language conventions, architecture, testing, git workflow, build commands. A backend domain may also need database/API conventions; a frontend domain may also need styling/a11y.

| Score | Description |
|---|---|
| **5** | All major areas covered well. |
| **3** | Core areas covered, notable gaps. |
| **1** | Many areas missing — agent will frequently guess. |

### 4. Consistency

**Contradictions inside the file or with other files in the stack?**

A common pattern is intentional layering: a global `CLAUDE.md` overrides a domain `CLAUDE.md` rule. That's not a contradiction — the prompt should recognise it. A genuine contradiction is two rules in the same scope that can't both be true.

| Score | Description |
|---|---|
| **5** | Fully consistent. |
| **3** | Minor tensions. |
| **1** | Outright contradictions. |

### 5. Actionability

**Can an AI agent actually execute these rules?**

"Use good judgment" is not actionable. "Run `./gradlew detektAll` before opening a PR" is.

| Score | Description |
|---|---|
| **5** | Every rule is agent-executable. |
| **3** | Most are executable; a few need human interpretation. |
| **1** | Many rules require human judgment. |

---

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

---

## Caveats

- AI scoring is non-deterministic. Run multiple times for sensitive comparisons.
- The model interpretation depends on the prompt. If a score feels wrong, the fix is usually in [`evals/prompts/config-quality.md`](../evals/prompts/config-quality.md), not the file under test.
- Schema validation (via `ajv-cli`) is optional. Without it, malformed output is detected by `jq` parse but not field-level checked.
