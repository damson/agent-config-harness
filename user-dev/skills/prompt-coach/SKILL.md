---
name: prompt-coach
description: >
  Use when the user asks "rate my prompt" / "evaluate my prompt(s)" / "how am I
  prompting?" / "give me prompt feedback" / "score my last prompt" / "4Ds analysis" /
  "prompt retrospective". Also use when the user asks for an end-of-session review of
  their work-with-Claude habits, OR after a session involving 20+ turns where the user
  explicitly wants improvement signal. NEVER fire unsolicited — prompt critique without
  consent is unwelcome.
---

# Prompt Coach — score prompts on the 4Ds framework

This skill scores the user's prompts on four dimensions, identifies the weakest, and proposes a rewrite. The goal is to make the user a more efficient operator over time — not to lecture.

Sibling skills:
- `brief-as-prod` — proactive (transforms terse prompts BEFORE execution).
- `skill-opportunity-finder` — surfaces repetition patterns to skillify.
- `prompt-coach` (this one) — retrospective scoring with concrete rewrites.

## The 4Ds framework

| Letter | What it measures | High score looks like | Low score looks like |
|---|---|---|---|
| **D**elegation | Trust in the assistant to choose how, not just what. | "Open the PR with whatever body you think best." | Specifying every option and decision; treating the assistant as a typewriter. |
| **D**escription | Clarity of subject + scope + expected output. | "Rebase PRs #3, #4 on develop, force-push, report one line each." | "Manage the open PRs." |
| **D**iscernment | Quality of feedback on the assistant's output — pushing back, validating, catching mistakes. | "PR description has a broken Mermaid line — fix it AND make sure future PRs lint for it." | Silent acceptance of low-quality output. |
| **D**iligence | Follow-through across turns — reminders, verification, applying new conventions retroactively. | "Apply this rule retroactively to open PRs and document it as a convention." | Letting promises drop; not surfacing missed commitments. |

Each scored **1–5**.

## Procedure

### Mode A — single prompt

When the user pastes / quotes one prompt and asks "rate this":

1. Read the prompt + the ~3 turns of session context around it.
2. Score each D from 1 to 5. Justify each with the specific cue in the prompt (or its absence).
3. Identify the **weakest D** and explain it in one sentence.
4. Propose **one rewrite** of the prompt that fixes that weakest dimension without inflating word count by more than ~30%.
5. Stop. Don't lecture.

Output template:

```
## Prompt evaluation

> <quoted prompt>

| D | Score | Why |
|---|---|---|
| Delegation | X/5 | <cue> |
| Description | X/5 | <cue> |
| Discernment | X/5 | <cue or N/A — not applicable in this turn> |
| Diligence | X/5 | <cue or N/A> |

**Weakest dimension**: <D> — <one-sentence diagnosis>

**Rewrite**:
> <better version, same intent, fixed weakest D>
```

### Mode B — session retrospective

When the user asks for an end-of-session or multi-prompt review:

1. Sample up to **8 representative prompts** spread across the session (not the first/last 3 — those are noisy).
2. Score each prompt on 4D (or skip a D if not applicable to that prompt).
3. Compute the **average per D** and a **session total** (X / 20).
4. Identify the **single weakest pattern** (which D is consistently low across prompts).
5. Pick **one concrete past prompt** as the case study — show the original and a rewrite.
6. If the pattern suggests automation, propose **one new skill** (defer to `skill-opportunity-finder` for the full proposal — just name it + one-line rationale here).

Output template:

```
## Session retrospective — 4Ds

Sampled <n> prompts.

| D | Average | Trend | Comment |
|---|---|---|---|
| Delegation | X.X | ↑ stable ↓ | <pattern across the session> |
| Description | X.X | ↑ stable ↓ | <pattern> |
| Discernment | X.X | ↑ stable ↓ | <pattern> |
| Diligence | X.X | ↑ stable ↓ | <pattern> |

**Session total**: X.X / 20

**Weakest pattern**: <D> — <2-sentence diagnosis>

**Case study (turn N)**:
> <original>

Rewrite:
> <improved>

**Skill opportunity**: `<kebab-name>` — <one-line rationale> _(see `skill-opportunity-finder` for the full SKILL.md draft if you want it)_
```

## 1–5 anchors per dimension

| D | 1 | 3 | 5 |
|---|---|---|---|
| Delegation | Every flag / option / step spelled out — assistant treated as typewriter. | Picks the goal, leaves micro-decisions. | States outcome + stop-condition; assistant picks tools and trade-offs. |
| Description | One verb, no subject, no scope ("Fix it"). | Verb + subject ("Fix the PR description"). | Verb + subject + scope + expected output + stop-condition. |
| Discernment* | Silent acceptance of wrong output. | Points out one issue. | Points out the issue, asks for root cause, adds a rule to prevent recurrence. |
| Diligence† | Drops follow-ups; misses skipped steps. | Returns to unfinished items eventually. | Tracks open commitments, applies new conventions retroactively, verifies before closing. |

*Discernment is only scored when the prompt REPLIES to assistant output.
†Diligence is scored across turns, not within one prompt.

If a D can't logically apply (e.g. first-turn prompt can't show Discernment) → write **N/A** and exclude from the average.

## When to STOP

- The user asks for evaluation of someone ELSE's prompt — defer; this skill is about the current operator's habits.
- The user is in the middle of a high-stakes operation (active incident, mid-merge) — defer with one line: "I'll run the retro after the operation lands."
- The user asks for the same evaluation a second time within the same hour — they're stalling; suggest concrete next action instead.

## What to NEVER do

- Don't moralize. The 4Ds are diagnostic, not judgmental.
- Don't suggest a rewrite that doubles the word count — the goal is denser, not longer.
- Don't grade Discernment or Diligence on prompts where those dimensions can't logically apply.
- Don't bring up old prompts the user didn't ask about, in Mode A. Mode B is the only place for cross-prompt patterns.

