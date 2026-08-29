---
name: redundancy-check-before-ship
description: >
  Use before committing an addition to any prose-rule file — CLAUDE.md, AGENTS.md,
  a docs/ page, a README, or a PR template. Fires when a diff ADDS conventions,
  rules or procedures in prose. Auto-trigger after writing such an addition and
  before `git commit`, and when the user says a file is "too big", "has
  duplicates", or asks whether a change "is really necessary". Skip for code,
  tests, config values, pure deletions, rewording that adds no rule, and new
  files with no sibling docs. For the CLAUDE.md-vs-sibling file-structure rewrite
  specifically, defer to `claude-md-pointer-check`; this skill covers rule-level
  dedup across any prose-rule file.
---

# Redundancy check before ship

Prose rules duplicate silently: the author recalls writing the sentence, not that
the repo already states it elsewhere. This skill greps each added rule against the
docs a reader already has loaded and reports what is genuinely net-new.

## Procedure

1. **Extract the rules the diff adds.** One *claim* per line, not one bullet per
   line. Split on every imperative verb and on `and` / `but` / `;` — a bullet
   reading "start from the template, never free-hand, and tick nothing you did
   not verify" is three rules, and each needs its own lookup.

2. **Grep for each rule's subject** across the files a reader might already have
   loaded: sibling pages in the same directory, the repo's `CLAUDE.md` /
   `AGENTS.md`, the PR template, `CONTRIBUTING.md`. Search the *subject*, not
   your phrasing — you will have reworded it.

   ```bash
   grep -rniE '<subject>' --include='*.md' . | grep -v node_modules
   ```

3. **For each already-stated rule, pick exactly one home.** Either keep the
   existing statement and drop the addition, or replace the existing one with a
   pointer to the new home. Prefer the location closest to the moment of use.

   The one exception is the entry-point/reference split — a rule may appear once
   in an always-loaded file and once in a reference doc when they sit at
   different distances from use. That is deliberate; anything else is drift.
   See the table below.

4. **Relocation is not free** — moving a block instead of deleting it still costs
   a reader. Test: **if the destination file has no existing section on the
   subject, drop the block rather than relocate it.** Relocation is justified
   only when it joins content it belongs beside.

5. **If the file claims to be portable or generic**, check the addition for
   hardcoded repo names, org names, bot accounts, CLI tools, or stack-specific
   paths — those contradict the claim and are the most common portability leak.

6. **Report** before committing: rules added / already stated elsewhere / net
   new, plus the file's line delta. If net new is zero, the diff is churn.

## Interpreting the result

| Finding | Action |
|---|---|
| Rule already stated in a sibling doc | Drop the addition; link instead |
| Rule stated in an entry-point file *and* a reference doc | Legitimate — different distance from use. Keep both, note why in the PR body |
| Rule appears in 3+ files | Collapse to one home; the others get a pointer |
| Addition restates the paragraph directly above it | Delete it |

## When to STOP and ask

- **More than ~15 added rules** — report the overlap and hand back rather than
  auto-pruning; a large doc restructure needs the author's judgement about which
  home is canonical.
- **The duplication looks intentional** — a safety rule deliberately repeated at
  entry point and point of use. Surface it, do not silently collapse it.
- **Removing a duplicate would leave a dangling pointer** elsewhere. Fix the
  pointer in the same change, or stop and say so.
- **The file is someone else's convention file** (another team's `AGENTS.md`) —
  report, do not edit.
