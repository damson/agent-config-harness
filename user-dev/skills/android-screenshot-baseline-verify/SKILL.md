---
name: android-screenshot-baseline-verify
description: >
  Use when checking that existing screenshot baselines still pass in any
  Android/Compose project — before pushing, after a refactor, a theme or design-token
  change, or a dependency bump. Fire when the user says "run the screenshots", "do
  the baselines still pass", "check the goldens", or asks whether a refactor changed
  the rendered output. Skip when the project ships its own verification skill. To
  create or update baselines rather than check them, use
  android-screenshot-baseline-record.
---

# Verify Android screenshot baselines

**A screenshot run that compares nothing reports success.** Run the plain unit-test
task instead of the verify task and the capture calls become no-ops: tests pass, zero
images are compared, and a refactor that changed every pixel ships clean. Green is not
the evidence — *comparisons performed* is.

## Procedure

### 1. Find the verify task — not the test task

```bash
./gradlew :<module>:tasks --all | grep -i "screenshot\|roborazzi\|paparazzi"
```

| Framework | Verify task | Not this |
|---|---|---|
| Roborazzi | `verifyRoborazzi<Variant>` | `test<Variant>UnitTest` |
| Paparazzi | `verifyPaparazzi<Variant>` | `test<Variant>UnitTest` |
| AGP preview screenshots | `validate<Variant>ScreenshotTest` | `<variant>ScreenshotTest` compile task |

The right-hand column runs the same test class and asserts nothing about pixels.

Where the variant sits differs by framework — last for Roborazzi and Paparazzi (`verifyRoborazziDebug`), in the middle for AGP (`validateDebugScreenshotTest`). Take the names from the command above; the table is the shape to look for, not the answer.

### 2. Confirm baselines exist first

```bash
BASE=$(find . -type d \( -name screenshots -o -name snapshots -o -name reference \) | head -1)
[ -n "$BASE" ] && find "$BASE" -name '*.png' | wc -l || echo "no baseline directory"
```

Zero baselines means there is nothing to verify and the run will pass vacuously, or fail for "missing golden" — which is a recording job, not a verification one. Send it to `android-screenshot-baseline-record`.

### 3. Run the verify task

```bash
./gradlew :<module>:<verify-task> --tests "<fully.qualified.TestClass>*"
```

### 4. Confirm comparisons actually happened

Do not accept the exit code alone. Ask the build for its own tally first, and only
fall back to hunting for artifacts:

```bash
# Roborazzi writes a machine-readable count — the direct answer to this step
find . -path '*/build/*' -name 'results-summary.json' -mmin -10 -exec cat {} +

# Any framework: reports and diff artifacts this run touched
find . -path '*/build/*' -mmin -10 \
     \( -path '*report*' -o -name '*compare*' -o -name '*diff*' \) | head
```

- **A summary states the comparison count** — Roborazzi's `results-summary.json` gives `total` / `unchanged` / `changed` / `added` directly. A non-zero `total` matching the tests you expect *is* the evidence; nothing further is needed.
- **A report was written this run and lists comparisons** — open it and confirm the entry count is above zero.
- **A diff image appears on failure.** A failure with no diff artifact means the comparison never ran; the failure is something else.
- **The log names each compared image** — re-run with `--info` if it is quiet.

Three things that make this step lie if you skip them:

- **No diff artifacts on a passing run is normal, not a no-op.** Comparison images are written only when an image differs. Absence of `*diff*` after a green run corroborates nothing either way — get the count from the summary instead.
- **`-mmin` is load-bearing.** Screenshot output directories are typically not cleaned between runs, so they accumulate images from earlier ones. Drop the time bound and stale evidence reads as current — the same class of bug this skill exists to prevent.
- **Never silence these commands with `2>/dev/null`.** A predicate `find` cannot parse then looks identical to "no evidence", and this step turns a good run into a false negative. `-newermt @<epoch>` is exactly that trap: a GNU extension BSD `find`, including macOS's, refuses to parse. `-mmin` is understood by both.

If none of these can be established, treat the run as **not having verified anything** and say so. Reporting an unverified run as passing is the exact failure this skill guards.

### 5. Prove the check can fail — once per setup

A verification you have never seen fail is not yet a verification. On first wiring, or whenever you are about to rely on it in CI:

1. Perturb something visible — change a padding, a colour, a string — in the composable under test.
2. Run step 3. **It must fail, and name the image.**
3. Revert, confirm the file is back (`git status` clean for that path), and re-run to green.

Report both halves: "fails when broken, passes when restored", quoting the failure line.

### 6. Read the diff before deciding what it means

Open the diff image (the second `find` in step 4 locates it — on a failure it will now have something to match) and decide which of three it is:

- **A regression** — fix the code, do not touch the baseline.
- **An intended visual change** — re-record (`android-screenshot-baseline-record`) and let the new baseline be reviewed as part of the diff.
- **Environment noise** — font, density, or renderer differs from where the baseline was recorded. Do not re-record to make it pass; that hides the drift and moves the problem to whoever records next.

## When to STOP

- **No verify task exists for the module.** The plugin is not applied there. Say so rather than falling back to the unit-test task, which would produce a meaningless pass.
- **Step 4 cannot establish that comparisons ran.** Report "could not confirm the run compared anything" — never upgrade it to "passing".
- **Every baseline fails at once.** A global font, theme, or density change, or baselines recorded on a different machine. Diagnose the shared cause; do not mass re-record.
- **The diff is ambiguous** — small anti-aliasing or subpixel differences. Confirm with the user whether a tolerance is appropriate rather than setting one to get to green.
- **The project ships its own verification skill or documented incantation.** Use it.

## Anti-patterns to avoid

- ❌ Running the plain unit-test task and reporting the pass — the silent no-op this skill exists for.
- ❌ Quoting "N tests passed" as screenshot coverage without establishing that N comparisons happened.
