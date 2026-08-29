---
name: android-screenshot-baseline-record
description: >
  Use when recording or re-recording screenshot-test baselines (golden images) in
  any Android/Compose project — Roborazzi, Paparazzi, or AGP's Compose Preview
  Screenshot Testing. Fire when the user says "record the baselines", "regenerate
  the screenshots", "update the snapshots", "the goldens are stale", or stages a
  new screenshot test with no images beside it. Skip when the project ships its
  own recording skill — that one knows its build's wiring. For checking existing
  baselines still pass, use android-screenshot-baseline-verify.
---

# Record Android screenshot baselines

A record run that writes nothing still exits 0 — skipped task, filter matching zero
tests, or output going somewhere you are not looking. Step 4 is what settles it.

## Procedure

### 1. Identify the framework before running anything

Its name decides the task, the baseline directory, and the failure modes:

```bash
grep -rn "roborazzi\|paparazzi\|screenshotTest" --include="*.gradle*" --include="*.toml" .
```

| Signal | Framework | Record task | Baselines live in |
|---|---|---|---|
| `io.github.takahirom.roborazzi` | Roborazzi | `recordRoborazzi<Variant>` | configured; often `src/test/screenshots` |
| `app.cash.paparazzi` | Paparazzi | `recordPaparazzi<Variant>` | `src/test/snapshots/images` |
| `com.android.compose.screenshot` | AGP preview screenshots | `update<Variant>ScreenshotTest` | `src/<variant>ScreenshotTest/reference` |

Where the variant sits differs by framework — last for Roborazzi and Paparazzi (`recordRoborazziDebug`), in the middle for AGP (`updateDebugScreenshotTest`). There is no single rule, so resolve the real names rather than assuming — `./gradlew :<module>:tasks --all | grep -i "screenshot\|roborazzi\|paparazzi"`. A task that does not appear is not wired to that module, and invoking it anyway is the quiet no-op this skill exists to catch.

### 2. Locate the baseline directory, then count what is in it

Do not guess it from the table — find where the PNGs actually are:

`<module>` is a Gradle path (`:app`, `:library:ui`); its directory is that path with
the colons turned into slashes. Resolve both once and reuse them:

```bash
GRADLE_MODULE=":app"                                   # yours
MODULE_DIR="${GRADLE_MODULE#:}"; MODULE_DIR="${MODULE_DIR//://}"
BASE=$(find "$MODULE_DIR" -type d \( -name screenshots -o -name snapshots -o -name reference \) | head -1)
echo "module dir: $MODULE_DIR   baselines: ${BASE:-<none yet>}"
[ -n "$BASE" ] && find "$BASE" -name '*.png' | wc -l
```

An empty `$BASE` means no baselines yet — read the plugin's output-directory setting
in the module's build file and set `BASE` to it before going on. Never run a bare
`find "$BASE"` while it is empty: that searches the whole tree and reports unrelated
PNGs as new.

Note the count. Without a before-number, "it recorded" is unfalsifiable.

### 3. Record, scoped to the test you mean

```bash
./gradlew :<module>:clean :<module>:<record-task-from-step-1> \
  --tests "<fully.qualified.TestClass>*"
```

`:clean` first. Screenshot plugins copy from an intermediates directory into the baseline directory, and a stale render left there by an earlier run is copied over the fresh one. `--rerun-tasks` and `--no-build-cache` do **not** clear intermediates; only cleaning does.

`--tests` narrows which tests *run*, not which baselines get *written*. Screenshot plugins commonly re-emit every golden the module owns, so expect all their mtimes to move even on a single-test re-record. The filter is still worth passing — it is just not the thing that makes step 4's answer trustworthy.

If the module has no `--tests` filter support for that task, run it unfiltered and rely on step 4 to tell you what actually changed.

### 4. Prove files were written — this is the whole point

```bash
if [ -z "$BASE" ]; then echo "BASE unset — stop, resolve it in step 2"; else
  find "$BASE" -name '*.png' | wc -l        # vs the step-2 count
  git status --short "$BASE"                # what this run actually changed
fi
```

`git status` is the one that matters, and it is the only command here that separates
the three outcomes: `??` is a new baseline, ` M` is a changed one, and a golden that
does not appear at all was re-emitted byte-identical. That last case is the common one
and it is invisible to anything time-based — a plugin that rewrites every PNG makes an
mtime check report the whole directory as new.

**No `??` and no ` M` after recording a test that had no baseline means the run recorded
nothing**, whatever the build said. Go back to step 1 — usually the task is not wired to
this module, or the filter matched no tests.

Where the baselines are not in version control, fall back to mtime and read the count as
an upper bound rather than a result:

```bash
find "$BASE" -name '*.png' -mmin -5         # touched in the last 5 minutes
```

(`-mmin` rather than `-newermt`: the `@<epoch>` form of `-newermt` is a GNU extension
that BSD `find`, including macOS's, rejects outright. `-mmin` is understood by both.)

### 5. Look at the images

Screen out the empty ones first, then view the rest with the Read tool — it renders PNGs:

```bash
find "$BASE" -name '*.png' -size -1k    # suspiciously small: blank or truncated
```

Reject and re-record if:

- **Blank, transparent, or zero-byte** — the test never captured, or captured before layout.
- **Unstyled: default sans-serif, white where the theme is dark** — the preview wrapper is bypassing the app theme. Wrap the composable in the real theme, not a preview-only wrapper: many wrappers key off an inspection-mode flag that is false under a screenshot runner, so they silently skip theming.
- **Only part of the component, or clipped** — the capture size is wrong; set an explicit device/size spec rather than re-recording and hoping.

A baseline is a contract. A wrong one locks in the wrong appearance and every future run agrees with it.

### 6. Commit the images with the test that produces them

```bash
git add "$BASE" "$(git status --porcelain | grep -oE '[^ ]*ScreenshotTest\.kt$' | head -1)"
```

One commit. Split across two, CI runs the test against goldens that are not there yet and fails on a change that is actually correct.

## When to STOP

- **No record task exists for the module** (step 1 found nothing). The plugin is applied at the root or to another module only. Say so — do not patch the build to force it; that is a build change needing its own review.
- **Step 4 shows no new files after two attempts.** Something structural is wrong. Report what you ran and what the directory holds; do not keep re-running.
- **Baselines change that your edit does not explain** — a shared theme, font, or density shift affects everything. Recording all of them buries the real diff; confirm the scope is intended first.
- **The project ships its own recording skill or documented procedure.** Use it — it knows the build's wiring, and this skill deliberately avoids assuming any.
- **A "temporary" build edit is needed to make recording work.** Stop and confirm. That edit forces record mode for every run that follows and must never be committed.

## Anti-patterns to avoid

- ❌ Recording to fix a failing verify without looking at the diff first. That is not a fix; it is overwriting the evidence.
