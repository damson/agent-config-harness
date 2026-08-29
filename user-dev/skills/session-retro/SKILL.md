---
name: session-retro
description: >
  Use ONLY when the user explicitly asks for an end-of-session retrospective —
  triggers like "session retro" / "end of session retro" / "session retrospective"
  / "wrap up the session" / "what did we learn this session" / "what should I
  take away from this session" / "let's reflect on this session". NEVER fire
  unsolicited — this skill produces evaluative feedback on the user's prompting,
  and reflection without consent is unwelcome. Skip when the session has fewer
  than ~15 substantive turns (signal too thin), when the user is mid-incident /
  mid-deploy, or when `prompt-coach`, `skill-opportunity-finder`, or
  `claude-md-management:claude-md-improver` has already been invoked in the
  current session.
---

# Session retrospective

Orchestrates three existing skills into one unified end-of-session report:

| Sub-skill | Lens |
|---|---|
| `prompt-coach` (Mode B) | How the user prompted — 4Ds scoring + weakest-pattern diagnosis |
| `skill-opportunity-finder` | Repeated patterns worth bundling into new skills |
| `claude-md-management:claude-md-improver` | Whether the project's CLAUDE.md files reflect what shipped |

The skill is a **signal** producer — it never applies changes itself. Each section ends with a "want me to act on this?" handoff so the user controls when to write.

## Procedure

### Step 1 — Pre-flight

1. **Count substantive turns**. Skip user messages that are < 10 words AND contain only acknowledgement words (`thanks`, `ok`, `yes`, `no`, `sounds good`, `nice`, `perfect`). Count the rest. Also capture the timestamp of the first counted message as `<session-start>` for the report. If the count is `< 15`, surface this and stop:

   > Session has only N substantive turns — too thin for a useful retrospective. Try again after a longer working block, or invoke `prompt-coach` / `skill-opportunity-finder` directly if you want one of the sub-axes scored now.

2. **Recency check (in-session)**. If `prompt-coach`, `skill-opportunity-finder`, or `claude-md-management:claude-md-improver` was already invoked in the current session, ask before re-running:

   > You ran `<sub-skill>` ~N turns ago. Re-run as part of the retro, or reuse that output?

3. **Operational state check**. If a high-stakes operation is in flight (active deploy, mid-merge with conflicts, mid-incident), defer with one line:

   > Retro deferred until the operation lands. Ping me again once it's done.

### Step 2 — Invoke `prompt-coach` in Mode B

Via the Skill tool: invoke `prompt-coach` with explicit Mode B framing ("session retrospective"). Capture the output verbatim.

Expected shape: 4Ds table (Delegation / Description / Discernment / Diligence), weakest-pattern diagnosis, one case study with rewrite.

If `prompt-coach` declines (e.g. the user said "ignore my prompts" earlier in the session), record the skip with a one-line reason and continue.

### Step 3 — Invoke `skill-opportunity-finder`

Via the Skill tool: invoke `skill-opportunity-finder`. Capture the output verbatim.

Expected shape: candidate skills in priority order, each with name + one-line rationale + one concrete past trigger. Each candidate ALSO carries a draft SKILL.md frontmatter — keep it in the captured output but do not write the file in this orchestrator.

### Step 4 — Invoke `claude-md-management:claude-md-improver` in report-only mode

Via the Skill tool: invoke `claude-md-management:claude-md-improver`. Capture output up to and including the per-file quality table and the proposed diffs. Do NOT request, accept, or forward any "apply these changes?" confirmation — the orchestrator is report-only. If the sub-skill prompts to apply, decline on behalf of the orchestrator and continue.

Expected shape: per-file quality table + recommended additions as diffs.

### Step 5 — Stitch the unified report

Single combined output, in this exact shape:

```markdown
# 🪞 Session retrospective

_Sampled <N> prompts across <M> substantive turns since <session-start>._

## 1. Prompting — 4Ds (via `prompt-coach`)

<Mode B output verbatim — the table, weakest D, case study>

## 2. Skill opportunities (via `skill-opportunity-finder`)

<Candidate skills, priority-ordered. For each: name + one-line rationale + past trigger. Defer the SKILL.md drafts to the underlying skill's output — link to it.>

## 3. CLAUDE.md currency (via `claude-md-improver`)

<Per-file quality table + recommended diffs. Report only — no applies.>

## 🎯 Suggested next actions

- **Prompting**: <weakest D — the one-sentence rewrite the user could try first>
- **New skill**: <#1 candidate name — file path it would land at>
- **CLAUDE.md**: <which file, what gap, est. lines of change>

Want me to drill into any of these? Apply the CLAUDE.md additions? Ship the top skill?
```

### Step 6 — Defer all writes

The skill ends with the report and a single question. No edits, no commits, no PRs in this orchestrator turn. The user picks the next action; the corresponding sub-skill or follow-up task handles the apply phase.

## Output discipline

- Keep the total report under ~80 lines for a typical 30-turn session. If any sub-skill's output is large, summarize in the stitch + link / refer to its full output.
- Preserve sub-skill output verbatim — don't paraphrase the 4Ds scores or the candidate names. The sub-skills are the source of truth on their own axis.
- The "Suggested next actions" section is YOUR synthesis. Pick exactly one item per axis. If a sub-skill returned nothing meaningful for its axis, write "(none — <axis> looks healthy)".

## When to STOP and ask

- **Someone else's transcript**: defer per `prompt-coach`'s rule — 4Ds is for the current operator's habits.
- **"Apply everything" before reviewing**: confirm explicitly before any sub-skill enters an apply phase. The user approves the slate; never opt them in by default.

(Pre-flight handles session-too-short, recency, and mid-incident in Step 1; sub-skill declines are handled inline in Steps 2–4.)

## What to NEVER do

- ❌ Apply CLAUDE.md edits or write SKILL.md files inline — the orchestrator is report-only; the user runs the apply phase.
- ❌ Lecture or moralize on prompting. The 4Ds are diagnostic, not judgmental.
- ❌ Bury "Skipped" sub-skills. If one of the three didn't run, say so up front in the report.
- ❌ Inline the sub-skill procedures. Always invoke via the Skill tool.
