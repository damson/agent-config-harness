---
name: refresh-domain-benchmark
description: >
  Use when the user asks to "rerun the benchmark", "show me all the scores",
  "compare android before/after", "score the configs", or any ad-hoc eval
  refresh outside of the `just sync` flow. Launches per-domain evals in
  parallel, waits for completions via notifications (no polling), renders the
  trend report, and optionally posts to a PR.
---

# Refresh domain benchmark

Wraps the parallel-eval + render cycle used in repos that follow the
`evals/run-eval.sh <domain>` + `benchmarks/report.sh` convention.

## Procedure

### 1. Determine target domains

Parse the user's request:
- Specific domain named (e.g. "rerun android") → single domain.
- "All" / unspecified → read `config/domains.conf` and use every domain.
- Comparison framing ("before/after", "without the X changes") → see step 2.

If more than 6 domains, ask the user before launching (rate-limit risk against
the Claude CLI).

### 2. Handle "isolated" / comparison runs

If the user asked for an isolated comparison (e.g. "run the benchmark without
the AGENTS.md changes"):

1. Stash a copy of the file: `cp <path> /tmp/<file>-stash.md`
2. Restore from baseline: `git checkout <baseline-ref> -- <path>`
3. Note the temporary state explicitly in the upcoming response so the user
   sees it.
4. After the eval completes, restore: `cp /tmp/<file>-stash.md <path>` (or
   `git checkout HEAD -- <path>` if HEAD already has the target state).
5. Verify clean tree with `git status -s`.

### 3. Launch evals in parallel

For each target domain, invoke the Bash tool with `run_in_background: true` on:

```bash
./evals/run-eval.sh <domain>
```

Each call returns a task ID and an output file path — remember both. Do **not**
poll the output files in a loop. The harness fires a `task-notification` event
when each background job exits; act on those notifications instead.

### 4. Collect outputs

When each task-notification fires, read its output file once via the Read tool.
The per-domain JSON written by `run-eval.sh` lives in
`evals/results/<date>-<domain>.json`. Extract:

```bash
jq -r '"\(.domain): \(.total)/25 \(.grade)"' evals/results/<date>-<domain>.json
jq -r '.findings[] | "  - [\(.dimension)] \(.section): \(.issue)"' evals/results/<date>-<domain>.json
```

Summarize for the user: per-domain score + grade + top 3 findings.

### 5. Render the trend report

```bash
./benchmarks/report.sh
```

Format as a markdown table for chat output. If presenting in a PR comment or
GitHub-flavored context, wrap the script output in a fenced code block so
unicode box characters render correctly.

If step 2 produced an isolated comparison run, label the affected domain row
explicitly in the summary table (e.g. `android (isolated: without AGENTS.md)`)
so readers can tell baseline rows from comparison rows. The on-disk score file
will have the same domain name as a normal run, so the label is presentation-only.

### 6. Optional: post to PR

Only if the user explicitly asked for a PR comment (or this skill was invoked
inside an open-PR context AND the user confirmed). Format:

```bash
gh pr comment <N> --body-file <markdown-table-file>
```

Never post without confirmation — comments are visible to others and not
cleanly revertable.

## When to STOP

- **`claude` CLI is missing or unauthenticated** → skip the eval step, run
  `./benchmarks/report.sh` against existing scores only, and tell the user no
  new eval was performed.
- **Working tree dirty** and step 2 not requested → ask before touching files.
- **More than one comparison axis at once** ("android without AGENTS.md *and*
  without .cursorrules") → ask the user to pick the most relevant one or to
  run a sequence. Combining multiple temp-restores is error-prone.
- **Evaluator non-determinism caveat:** if the user is making a trend claim
  off a single run, mention that the evaluator varies ±1–2 on borderline
  scores. Suggest N≥3 averages for anything quoted as a result.
- **Score file write fails** (full disk, schema mismatch) → surface the raw
  Claude output, do not silently lose the run.
