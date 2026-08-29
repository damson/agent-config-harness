---
name: save-before-compact
description: >
  Use ONLY when the user explicitly wants to compact a long session without
  losing its learnings — triggers like "save before compact" / "wrap up and
  compact" / "session's too long, compact but keep the takeaways" / "capture
  learnings then compact". NEVER fire unsolicited. This skill APPLIES changes
  (CLAUDE.md / preference-file additions, memory, new skills) and writes a resume
  brief, then stops for the user to run /compact — it never runs /compact itself.
  Skip when the session has < ~15 substantive turns (too thin to have learnings),
  when a high-stakes op is in flight (deploy, mid-merge, incident), or on someone
  else's transcript.
---

# Save before compact

A self-driving pre-compaction gate: capture what the session taught (each addition
approved and scored), suggest and optionally create skills, snapshot how to
resume, then stop for the user to run `/compact` — the one action the skill cannot
take itself.

## Procedure

Run a task per step, in order. Any step can short-circuit per its stated skip
conditions.

### Step 1 — Pre-flight

- Count substantive turns (ignore < 10-word acknowledgements: `thanks`, `ok`,
  `yes`, `nice`). If `< 15`, say so and skip straight to the resume brief (Step 8)
  — a thin session has nothing worth persisting.
- Detect context: is there a `CLAUDE.md` / `AGENTS.md` nearby? a domain registry
  (`config/domains.conf`)? an eval harness (`just eval` / `evals/run-skill-eval.sh`)?
  Record what's available — later steps branch on it.
- Defer (one line, then stop) if a high-stakes op is in flight — scan the last
  ~5 turns for a deploy / merge / rebase / migration / incident command whose
  completion was never confirmed — or if this is another operator's transcript.

### Step 2 — Reflect & route

List candidate facts under these categories: commands discovered, code-style
patterns followed, testing approaches that worked, environment/config quirks,
gotchas, decisions made. Then apply the **keep-test** — keep a fact only if (a) it
would prevent a mistake a capable future session would realistically make (not
restate the default behaviour, or what a neighbouring directive/test already
implies) and (b) it is not already stated in an existing config/CLAUDE.md file.
When unsure, drop it: a weak addition bloats the file and lowers eval scores; a
missed one costs nothing. For each keeper, pick a target — **versioned first**:

| Target | For |
|---|---|
| `CLAUDE.md` / `AGENTS.md` (team-shared) | Repo-wide facts future sessions need |
| personal preference files (whatever the config repo calls them) | Personal cross-project preferences |
| memory store (`~/.claude/…/memory/`) — **last** | Durable facts fitting no versioned file (un-versioned, lowest priority) |

Respect repo conventions: don't fatten a file the repo keeps as a one-line pointer
to a sibling; keep whatever style and secret-lint rules it enforces; match the
target file's format.

### Step 3 — Draft (brevity gate)

One concept per line, minimal, in the target's format. Anything that failed the
Step 2 keep-test, or restates an existing line, does not get drafted. Shorter is
better as long as it stays relevant and performant.

### Step 4 — Assess (per-item approve)

Show each addition as a diff: **target · why (one line) · the line**. The user
**applies or skips each**. Write nothing without approval. Keep an
applied/skipped ledger.

### Step 5 — Verify & score

After applying:
- **Structural**: if any skill file was touched, `bats tests/skills.bats`;
  otherwise sanity-check the edited file still parses/renders.
- **Score** the changed files: `just eval <domain>` / `run-skill-eval.sh` if the
  harness exists (read the score from `evals/results/…-RAW.txt`, stripping ```json
  fences); otherwise an inline rubric on the 5 dimensions (clarity, conciseness,
  completeness, consistency, actionability).
- A score regression or a violated rule (pointer, em-dash, secret) → surface it
  and offer to tighten or revert. Never silently ship a regression.

### Step 6 — Memory (lowest priority)

Only durable facts that fit no versioned file. Write per the memory-file
convention (frontmatter + one fact) and add the one-line `MEMORY.md` pointer.
Skip entirely if no memory store exists.

### Step 7 — Suggest & create skills

Invoke `skill-opportunity-finder` (Skill tool) to surface repeated patterns worth
a new skill. Present each candidate — name · one-line rationale · concrete past
trigger. For each the user **approves, create it now, before compaction**, via the
skill-verification loop: write the new `SKILL.md` → run the repo's skill structure
tests → score it with the repo's eval command (inline rubric where no harness) →
address actionable findings (**B ships**). Same assess → verify → score discipline
as Step 4–5. Creation runs here, not after `/compact`, because authoring a good
skill needs the live session context compaction discards. Declined candidates go
into the resume brief for later. Skip the step if no repeated pattern surfaced.

### Step 8 — Resume brief

Compose a tight *pick-up-here* note: **Goal · Done · Next actions · Open
questions · Key files/commands/decisions**. Save it, then mirror it to a stable
pointer:

```bash
repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-'); : "${branch:=nobranch}"
ts=$(date +%Y%m%d-%H%M%S)
sid=$(echo "${CLAUDE_SESSION_ID:-$PWD}" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1); : "${sid:=nosession}"
dir=.claude; mkdir -p "$dir" 2>/dev/null || dir="$SCRATCHPAD"   # fallback if repo not writable
f="$dir/${repo}-${branch}-${ts}-${sid}.md"
```

Write the brief to `$f` and copy it to `$dir/session-resume-latest.md` so a
post-compact "read the latest brief" always resolves. Echo the brief inline — the
file survives compaction where an inline note may be compressed.

### Step 9 — Compact handoff

Print the ledger (applied / skipped / scores / memory written / **skills
created**), any declined skill suggestions, and the resume-brief path. Then say:

> Learnings saved and verified, resume brief at `<path>` — safe to run `/compact`
> now. I'll read it to pick up.

Stop. The user presses `/compact`.

## When to STOP

- **Nothing to save** — thin session (Step 1), or the user skipped every addition
  → no writes; go straight to the resume brief + handoff.
- **No per-item approval** → do not apply an addition or create a skill; a
  declined skill is recorded in the resume brief, not created.
- **No eval harness** → inline rubric, and say so; never claim a `just eval` score
  that wasn't produced.
- **Score regression / violated rule** (pointer, em-dash, secret) → surface and
  offer to tighten or revert; do not ship silently.
- **High-stakes op in flight, or another operator's transcript** → defer with one
  line and stop.
- **Resume brief** stays a tight pick-up note, never a transcript.
