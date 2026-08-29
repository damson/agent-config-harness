---
name: skill-opportunity-finder
description: >
  Use when you notice the user repeating the same instruction / asking the same kind of
  question / correcting you on the same kind of mistake / doing the same manual
  operation three or more times in a session. Also trigger when the user explicitly
  asks "what should be a skill?" / "what am I doing manually?" / "where am I repeating
  myself?". Skip during the first ~5 turns of a session — patterns need history to be
  observable.
---

# Skill opportunity finder

A skill is justified when **the same shape of work happens three or more times** in a session (or across sessions) and a procedural recipe would have caught it. This skill scans the recent conversation for those patterns and proposes new skills.

## What to look for

### Pattern A — Repeated user corrections
The user has told me the same thing in two or more turns:
- "always do X before Y"
- "don't forget to X"
- "make sure X is always Y"
- A correction on the same kind of artefact (PR body, commit message, diagram syntax)

If 3+ corrections of the same shape → propose a skill that enforces the rule.

### Pattern B — Repeated manual operations
The user has performed (or asked me to perform) the same multi-step operation three or more times:
- "rebase + push + verify"
- "draft + screenshot + paste"
- "fetch + read comments + reply"

If 3+ instances → propose a skill that bundles the procedure.

### Pattern C — Repeated discovery work
I (the assistant) keep re-discovering the same information at the top of new turns:
- Re-checking PR status
- Re-listing worktrees
- Re-reading the same file

If the work is mechanical and the answer changes only when external state changes → propose a skill that wraps the discovery.

### Pattern D — Repeated meta-instructions to me
The user has given me the same process directive multiple times:
- "review the comments after every push"
- "tag me in the comment"
- "use git flow not direct pushes"

If the directive applies broadly → propose a skill that auto-applies it.

## Procedure

1. **Scan the last 30+ turns** (or the whole session if shorter) for the four patterns above.
2. **Cluster** corrections / operations by **shape**. Two events share a shape when they meet ALL of:
   - **Same artefact class** — both about commits, both about PR bodies, both about migrations, etc.
   - **Same verb family** — "fix / repair / patch" cluster; "list / show / report" cluster; "rebase / rewrite / squash" cluster.
   - **Same trigger boundary** — both reactive ("after push", "after merge") or both proactive ("before opening PR").

   If 2 of the 3 match, treat them as the same shape but require ≥4 instances before proposing. All 3 match → 3 instances is enough.
3. **For each candidate**, draft a SKILL.md layout with:
   - **name**: kebab-case, verb-first or noun-first depending on shape
   - **description**: the auto-trigger condition. Be specific about WHEN to fire — bad triggers spam, good triggers stay quiet
   - **procedure**: numbered steps the skill performs
   - **when to STOP**: edge cases where the skill should hand back to the user
4. **Present candidates in priority order** (highest-frequency / highest-friction first).
5. **Show one concrete past example** for each — a specific moment in the session where this skill would have helped.

## Output shape

```markdown
## Skill opportunities found in this session

### 1. <name> — <one-line rationale>

**Past trigger (turn N)**: "<verbatim user line that would have fired the skill>"

**Draft SKILL.md**:
```
---
name: <kebab-case>
description: <auto-trigger conditions>
---

# <Title>

<2-4 sentences explaining purpose>

## Procedure
1. ...
2. ...

## When to STOP
- ...
```

### 2. <name> — <one-line rationale>
...
```

## When to STOP

- **No candidates pass the shape filter.** Report "no patterns yet" — don't manufacture a candidate to justify firing.
- **The session is < 5 substantive turns** (greetings, single-prompt questions). Patterns need history; defer with one line.
- **The cluster is genuinely ambiguous.** Two events match on artefact but differ on verb AND trigger — surface to the user instead of guessing.
- **The user declines a proposal.** Don't re-propose the same candidate later in the same session.
- **A matching skill already exists.** Check the skills available in this session before proposing one; point at it instead of creating a duplicate.

## What to NEVER propose

- Skills that fire on EVERY turn (no useful trigger) — they're really CLAUDE.md content.
- Skills for one-off operations unlikely to recur.
- Skills that pre-empt user judgment (e.g. "auto-merge any CLEAN PR") — defer to the user on irreversible decisions.

## How to decide between a skill and a CLAUDE.md note

| Property | Skill | CLAUDE.md note |
|---|---|---|
| Triggers on specific user words / actions | ✅ | ❌ (always loaded) |
| Has a multi-step procedure | ✅ | ❌ (one-liner reminders) |
| Can decline to fire (when a condition isn't met) | ✅ | ❌ (passive) |
| Reusable across projects | ✅ | rarely |

When in doubt: if you'd write "ALWAYS do X" or "NEVER do Y" — CLAUDE.md. If you'd write "WHEN <trigger> THEN <procedure>" — skill.
