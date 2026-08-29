---
name: agent-config-audit
description: >
  Audit AI agent configuration files (CLAUDE.md, AGENTS.md, preferences.md) for contradictions,
  duplication, bloat, and personal/team boundary violations. Resolves the symlink chain to confirm
  which files are actually loaded for the current project, then cross-checks them for issues.
  Use when config files feel stale, when onboarding to a new project, or after restructuring your
  config repo. Pass --fix to propose and apply edits after reporting.
---

# Agent Config Audit

Audit the AI instruction files active for the current project. Report findings, optionally fix them.

## Step 1: Resolve the Active File Stack

From the current working directory, resolve which files Claude actually loads:

1. **Global CLAUDE.md** — `~/.claude/CLAUDE.md` (follow symlink to source)
2. **Global preferences** — `~/.claude/preferences.md` (follow symlink to source)
3. **Project AGENTS.md** — look for `AGENTS.md` in the project root (follow symlink to source)
4. **Project CLAUDE.md** — look for `CLAUDE.md` in the project root (follow symlink chain fully)
5. **Project preferences** — `.claude/preferences.md` in the project root (follow symlink to source)

For each file found, report:
- The logical path (e.g. `<project>/AGENTS.md`)
- The resolved source path (e.g. `<config-repo>/workspace/<domain>/AGENTS.md`)
- Whether it is personal or team-owned

Print the stack before running checks so the user knows the scope.

## Step 2: Run Checks

For each finding, record: severity (`🔴 Contradiction` / `⚠️ Duplication` / `📦 Bloat` / `🚧 Boundary violation` / `✅ OK`), file + section, and a recommended fix.

### 2a — Personal/Team Boundary

Team files (`AGENTS.md` in the project repo) should contain **only** team conventions — rules agreed upon by the whole team. Flag any of the following if found in a team file:

- Personal commit style preferences (e.g. no pod prefix, "Extract" wording)
- No-AI-signature rules
- Worktree tool commands (`git gtr`, etc.)
- Personal story point sizing
- Personal tool shortcuts or aliases

Conversely, flag if team conventions are **missing** from personal files when they should be there for portability to new projects (e.g. architecture rules, testing conventions that the personal user always wants applied).

### 2b — Contradictions

For each topic that appears in multiple files (commit format, naming, testing framework, etc.), compare the rules:

- If the rules agree → `✅ OK`
- If they differ, determine whether the difference is **intentional layering** (personal file overrides team file — acceptable) or a **genuine conflict** (two rules in the same scope that can't both be true)
- Flag genuine conflicts as `🔴 Contradiction` with both locations and both values

Example of intentional layering (not a conflict):
> Team AGENTS.md: "commit format `<pod>: <description>`"
> Personal CLAUDE.md: "no pod prefix in commits"
> → Personal overrides team. This is correct — squash-merge adds the pod prefix.

### 2c — Duplication

For each rule or section, check if the same content (verbatim or near-verbatim) appears in multiple files:

- Same file, different section → likely bloat in one of them
- Same content in global preferences AND global CLAUDE.md → one is redundant; flag which to remove
- Same content in project CLAUDE.md AND team AGENTS.md → check if it's intentional cross-project portability or accidental

Report: source file + section, duplicate file + section, and recommendation (keep in X, remove from Y, or "intentional — leave both").

### 2d — Bloat

Within each file, flag:

- Sections that are pure recaps of other sections in the same file (summary/reminders sections that restate earlier rules verbatim)
- Generic non-actionable advice ("organize them logically", "follow best practices")
- Reference material that could be a single pointer line (e.g. a list of 5 doc subdirectories that could be "docs in `/docs/`")
- Standard-knowledge rules that any competent developer would know and that add noise without guidance (e.g. "Classes: PascalCase" in Kotlin)
- Procedural checklists that assume the agent is doing human-only steps (verify these are actually agent-actionable before flagging)

### 2e — Structural health

- Check that each file's symlink chain resolves to a real file (no broken links)
- Check that project preferences are symlinked to the config repo (not standalone copies that can drift)
- Check that global preferences are symlinked to the config repo

## Step 3: Report

Print a structured report:

```
## Agent Config Audit

### Active File Stack
| Logical path | Source | Owner |
|---|---|---|
| ~/.claude/CLAUDE.md | `<config-repo>/<personal-layer>/CLAUDE.md` | personal |
| ... | ... | ... |

### Findings

🔴 Contradiction — [file:section] vs [file:section]
  Both files define commit format but with conflicting rules.
  Recommendation: ...

⚠️ Duplication — [file:section] duplicates [file:section]
  Recommendation: keep in X, remove from Y

📦 Bloat — [file:section]
  "Important Reminders" restates 9 rules already defined earlier in the same file.
  Recommendation: remove section

🚧 Boundary violation — [file:section]
  Personal rule "no pod prefix" found in team AGENTS.md.
  Recommendation: move to personal CLAUDE.md

✅ OK — [N] rules checked, no issues
```

If no issues are found, say so clearly.

## Step 4: Fix (only with `--fix`)

For each finding that has a clear fix:

1. Show the user the proposed edit (before/after diff or description)
2. Ask for approval per finding, or ask "apply all?" for a batch
3. On approval, apply the edit using the Write or Edit tool
4. After all edits, print a summary of what changed

Do **not** apply fixes without explicit approval. Do **not** batch-apply without asking first.

## Flags

| Flag | Description |
|------|-------------|
| `--team` | Audit only the team AGENTS.md |
| `--personal` | Audit only personal files (CLAUDE.md, preferences) |
| `--fix` | After reporting, propose edits and apply on approval |

## When to STOP

- **Cannot resolve the file stack** (symlinks broken, files missing) → stop and surface the breakage; do not invent file contents.
- **Active project is not managed by a config repo** (no symlinks back to one) → report findings but do not propose fixes that assume one.
- **`--fix` requested but the finding has no unambiguous fix** → describe the trade-off, let the user choose; never auto-pick.
- **Findings touch shared/team files the user does not own** → flag and stop; the user must decide whether to PR upstream.
