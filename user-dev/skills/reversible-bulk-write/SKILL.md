---
name: reversible-bulk-write
description: >
  Use when about to write in bulk to a live datastore — importing a dataset,
  backfilling a column, a mass UPDATE, any statement whose blast radius is
  "lots of rows". Fire before the first write, not after it goes wrong. Also
  fire when a bulk write has already gone in and needs undoing. Do NOT fire for
  ordinary single-row writes, for schema migrations (those have their own
  review and apply path), or for writes to a throwaway or local database.
---

# Reversible bulk write

A bulk write is judged by what you can undo, not by what you intended.

## Procedure

1. **Name the invariant.** One measurable fact this write must NOT change, and
   its value right now — "`entries` stays 1,541", "no row leaves `approved`".
   Record the number before touching anything. Without it, "did that go
   correctly?" has no answer, only a vibe.
   - Default when nothing obvious presents itself: `count(*)` on the table the
     write must NOT reach, and on the constrained subset it should. Two
     numbers, taken before.

2. **Dry-run every stage before applying any stage.** Multi-step pipelines are
   where this bites: stage 1 accepts what stage 2 rejects, and applying stage 1
   first buys you a write plus a rollback for nothing. Run the whole chain in
   dry-run, read the projected counts, and only then apply.
   - Counts that look *too clean* (100%, 0%, exactly N) deserve a second look
     before you trust them.

3. **Write the rollback before applying, and prove its columns exist.** Query
   `information_schema.columns` or read the migration — do not guess a foreign
   key's name. A rollback that fails on a typo, written while the bad data is
   already live, is the worst moment to be discovering the schema.
   - Scope it to what THIS operation created: an `intake_source`, a batch id, a
     timestamp window. Never a bare `delete from <table>`.
   - Check what the scope would catch that you did not create — pre-existing
     rows sharing the marker survive only if you exclude them explicitly.
   - A pipeline writes to several tables; the rollback must clear all of them,
     in foreign-key order, or the next run trips over the remains.

4. **Apply, then re-check the invariant** and the counts you projected in
   step 2. A projection that missed by a lot means the dry run modelled
   something other than what ran.

5. **Report both numbers** — before and after, plus the invariant. "Queue
   598 → 2,371, `entries` unchanged at 1,541" is a verifiable claim;
   "imported successfully" is not.

## Sharp edges

- **A derived artefact does not know about state added after it was derived.**
  A file labelled "new candidates" means new against whatever existed when it
  was written. Re-check novelty against the live target, not the label.
- **Interrupting mid-write leaves a partial state**, not a clean one. Stop the
  job, then roll back explicitly — do not assume the abort was atomic.

## When to STOP

- **It turns out to be a migration.** If the change is structural rather than
  data, hand off to the migration path — it has its own review and apply gate.
- **No rollback is possible** (an external API call, an irreversible delete, a
  third-party write). Say so plainly and get explicit confirmation before
  proceeding — do not proceed on the assumption that it will be fine.
- **The invariant cannot be stated.** If nothing measurable should stay
  constant, you do not yet understand the blast radius. Work that out first.
- **The dry run and the apply disagree** on counts. Stop and reconcile; do not
  "re-run and see".
