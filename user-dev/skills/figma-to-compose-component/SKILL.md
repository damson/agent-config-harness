---
name: figma-to-compose-component
description: >
  Use when building or recreating a Jetpack Compose component from a Figma design
  in any Android project. Fire when a figma.com/design or figma.com/file link is
  paired with "build this", "implement this component", "recreate this in Compose",
  or a ticket references a Figma node id. Covers retrieving the node without
  flooding context, checking the design system before writing anything new, and
  binding to theme tokens rather than raw values. Skip when the project ships its
  own design-system skill — that one knows its component catalogue.
---

# Build a Compose component from a Figma design

## Procedure

### 1. Read the node, not the file

A Figma *file* fetch returns megabytes of unrelated frames. Extract the node id
from the URL (`…/design/<fileKey>/<name>?node-id=<id>`) and request that node
alone, through whichever Figma integration the environment offers.

Ask for, in this order, stopping when you have enough:

1. **Node metadata** — layout, spacing, fills, typography, component name.
2. **The variant set**, if the node is one of several states.
3. **One rendered image** of the node, for visual comparison only.

If no Figma integration is available, ask for an export of the node's properties
or a screenshot with the spacing/colour values stated. Do not infer hex values
from a screenshot — a compressed image does not carry exact colour.

### 2. Search the design system before writing anything

Find the module the theme lives in — that is the design system, whatever it is called:

```bash
grep -rln "MaterialTheme\|ProvideTextStyle\|lightColorScheme" --include="*.kt" . \
  | sed 's|/src/.*||' | sort -u
grep -rn "<ComponentName>\|<SimilarConcept>" --include="*.kt" <that-module>/
```

Take that output as the answer rather than pre-judging it:

- **Several lines** → the design system is the shared UI module among them, not a feature module.
- **One line** → the project is single-module. The theme lives in the app, so the app *is* the design system; read `<that-module>/` as the app module for the rest of this skill.

There is no "this project has no design system" outcome — only a smaller one.

Then decide, explicitly:

- **Exists and fits** → use it. Say which component and stop.
- **Exists and nearly fits** → extend it (new variant/parameter). Cheaper than a sibling and keeps one behaviour.
- **Genuinely new** → build it, in the design-system module if it is reusable, in the feature module if it is not.

State which of the three you chose and why. Skipping this step is how a catalogue
acquires three near-identical buttons.

### 3. Map every Figma value to a token

Walk the node's properties and resolve each to a theme accessor — spacing, colour,
typography, shape, elevation:

```bash
grep -rn "val spacing\|val colors\|val typography\|val shapes" \
  --include="*.kt" <that-module>/ | head -40          # a custom token scale?
grep -rnE "(object|fun) [A-Za-z]*Theme" --include="*.kt" <that-module>/ | head
grep -rn "MaterialTheme\." --include="*.kt" <that-module>/ | head
```

A theme is as often a `@Composable fun <Name>Theme` as it is an `object`, so match both —
and a project can perfectly well have a theme and no token scale of its own.

**What you find decides what counts as a token:**

- **A custom scale** (`spacing`, a typography object, semantic colours) — bind to it. Raw `.dp`, `.sp` and `Color(0x…)` in the finished component are the defect.
- **Material only, no custom scale** — `MaterialTheme.colorScheme.*`, `MaterialTheme.typography.*` and `MaterialTheme.shapes.*` are the tokens. Bind colour, type and shape to them; there is no Material spacing scale, so spacing is raw `.dp` and that is correct, not a defect. Keep the values consistent across the component rather than inventing a token layer to satisfy a rule.

Two carve-outs on top, both deliberate: a value the design system genuinely does not
model, and a true one-off like an asset's intrinsic size. Anything else, find the token.

**When a value sits between two tokens, ask.** Picking the nearer one silently
introduces a design inconsistency that is invisible in review and hard to trace
later.

### 4. Build it with a preview

Keep the component stateless: parameters in, events out, no view model, no
navigation. State is hoisted by the caller.

Add a `@Preview` per meaningful state — default, and whatever the variant set in
step 1 showed (disabled, error, selected, long text, RTL if supported). The
preview is what the screenshot test captures, so a state without a preview is a
state without coverage.

### 5. Cover it with a screenshot test, then record

Write the screenshot test, then record its baselines — `android-screenshot-baseline-record`
if the project has no recording skill of its own. Recording is what proves the capture
picked up the theme rather than rendering unstyled.

### 6. Compare against the design

Put the recorded image beside the step-1 render and check, in order: overall
proportions, spacing rhythm, typography weight and size, colour, then corner and
border treatment. Report differences you are leaving in place and why — a
deliberate deviation stated is fine, an unnoticed one is a defect.

## When to STOP

- **The design system already has it** (step 2). Say so and stop. Building the duplicate anyway is the most expensive outcome here.
- **The Figma node cannot be retrieved** and only a screenshot is available. Build the structure, but stop before asserting exact colours or spacing — ask for the values.
- **The design uses a token that does not exist** in the theme — a named colour, type ramp or elevation with no counterpart. Adding one is a design-system decision, not a component one; surface it. This is not the same as a project having no scale for that dimension at all (step 3): there, use the value directly and move on.
- **The node is a whole screen, not a component.** Split it and confirm the decomposition before building — a screen built as one component cannot be reused or tested per state.
- **The design contradicts an existing component's established behaviour** (a different disabled treatment, say). Raise it; do not encode two answers to the same question.

## Anti-patterns to avoid

- ❌ Reading a colour off a rendered image. A compressed PNG does not carry the exact value; get it from the node or ask.
