# What a score looks like

Real output, committed so you can see the product without an API key. One
config, one edit, and the number moved, which is the entire pitch.

| File | What it is | Score |
|---|---|---|
| [`../../workspace/backend-node/CLAUDE.md`](../../workspace/backend-node/CLAUDE.md) | The example domain config, as shipped | **24/25 (A)** ([`scored-A.json`](scored-A.json)) |
| [`degraded.md`](degraded.md) | The same file plus two sections of familiar rot | **12/25 (F)** ([`scored-F.json`](scored-F.json)) |

The rot is the kind config files actually accumulate, not sabotage:

- a **"General guidance"** section of platitudes ("write clean, maintainable
  code", "organize modules logically"), and one new rule that quietly
  contradicts the Testing section;
- an **"Important reminders"** section restating seven earlier rules verbatim:
  the second copy that drifts.

The rubric caught all of it by name: the contradiction under `consistency`,
the verbatim restatement under `conciseness`, the platitudes under
`actionability`. Diff the two configs, then diff the two findings lists.

Reproduce (needs the Claude CLI and an API key):

```bash
./evals/run-eval.sh backend-node
```

Scores move ±1–2 on borderline runs: an A and an F are a signal, two runs one
point apart are not. `docs/evaluation.md` has the rubric.

Both runs are rubric 2, where the scores are computed from the findings rather
than judged alongside them: the good file draws one minor finding, and the
rotted one draws majors in four dimensions. `just calibrate` re-runs exactly
this pair and fails if the gap between them closes.
