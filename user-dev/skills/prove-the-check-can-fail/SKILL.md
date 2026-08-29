---
name: prove-the-check-can-fail
description: >
  Use when adding or relying on a test, assertion, screenshot golden, lint rule or CI
  step meant to catch something, before trusting it or reporting it as coverage. Also
  fire when wiring a check into CI, when a check passes on its first run having never
  been seen red, or when the user asks "does that actually test anything" / "is that
  really covered". Do NOT fire for test-driven work, where the test was already seen
  failing before the fix.
---

# Prove the check can fail

A green check is not evidence until it has been seen red: passing proves it ran, only
failing proves it was looking at the right thing. A check that cannot fail is worse
than no check, because it gets reported as coverage.

Complements `superpowers:verification-before-completion` — that skill asks "did the
command pass?", this one asks "would it have caught the bug?".

## Procedure

1. **Name the defect.** One sentence: what wrong state does this check exist to
   catch? If that cannot be stated, the check has no purpose yet — fix that first.

2. **Introduce the defect.** The smallest edit that produces it: corrupt the golden,
   invert the condition, delete the guard, remove the `await`. Prefer a temporary
   edit you can revert exactly: `cp <file> "$TMPDIR/orig"` first, restore with
   `cp "$TMPDIR/orig" <file>`. Never `git checkout <file>` — that also discards any
   uncommitted work the file already had.

3. **Run the check the way CI runs it.** Same task, same flags. Then read the output.
   - **Still green → the check is inert.** Stop. This is the finding, and it matters
     more than whatever you were originally doing. Find out why before continuing.
   - **Suspiciously fast → suspect caching.** A build tool reporting success in under
     a second usually skipped the work. Re-run with `--rerun-tasks` (Gradle),
     `--no-cache` (jest), `--force` (cargo) or the equivalent. **A cached pass is not
     a pass**, and a cached pass during this step invalidates the whole experiment.
   - Confirm the failure message actually names the defect you introduced. A check
     failing for an unrelated reason has still not been validated.

4. **Restore and re-run.** Confirm green from the restored state, not from cache.
   Verify the working tree is back to where it started: `cmp "$TMPDIR/orig" <file>`
   and `git status`.

5. **Report both halves.** "Fails when broken, passes when fixed", with the failure
   message quoted.

## Sharp edges

- **Assertions that silently no-op.** Some frameworks only assert when driven by
  their own runner — screenshot libraries are the classic case, where the ordinary
  test task captures nothing and passes regardless. Step 3 is how you find out.
- **Environment-gated rendering.** A test asserting on pixels, layout or graphics can
  pass against a stub that draws nothing. Introduce a visible defect and confirm the
  check notices it.
- **Generated artifacts get regenerated.** If the check reads something a generator
  produces (an installed hook, a rendered config, a build output), degrade the
  *generator*. Degrading the artifact proves nothing: a setup step or an
  earlier-ordered test rebuilds it, and the check goes green against the repaired
  copy. Have the check produce what it asserts on, so it cannot pass on a stale one.
- **CI ≠ local.** If the check is meant to guard CI, prove it fails *in the CI
  invocation*, not just in a local one-off command.
- **A check that shares its rule with what it checks proves nothing.** A scan that
  confirms a regex by running that regex counts its own false positives as
  confirmations. Validate with a DIFFERENT rule — the near-miss it must not match,
  or the side you did not count.
- **A run that read nothing reports perfectly.** Over an empty input set every
  assertion holds — 0 failures, all green, indistinguishable from a clean run.
  Assert on the INPUT count (files opened, rows read) before believing the result:
  a partial run produces a believable figure and gets quoted.

## When to STOP

- **Test-driven work** — the test was already seen failing; do not redo it.
- **Breaking it is unsafe or irreversible** (production data, a live migration, a
  destructive deploy). Reason it through instead, and say plainly in the report that
  the check was not empirically falsified.
- **Third-party check with a documented, trusted failure mode** — point at the
  documentation rather than staging a failure.
- **The defect cannot be introduced without a large rewrite.** Say so; that itself
  suggests the check is coupled to something it should not be.
