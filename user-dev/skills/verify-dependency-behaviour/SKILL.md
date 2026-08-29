---
name: verify-dependency-behaviour
description: >
  Use when about to state or rely on how a third-party JVM/Android library behaves —
  a default value, whether a field is omitted or null, which branch a task takes —
  and the docs are absent, ambiguous, or the naming suggests something the code may
  not do. Fire when a plan says "set X to its strict value" without evidence X is not
  already strict, when a field's name and its type disagree, or when a check passes
  and you cannot say which comparison it made. Do NOT fire when the behaviour can be
  run and observed — run it.
---

# Verify dependency behaviour from the artifact

A library's name, its field names and its README are all claims. The bytecode is what
runs. Where they disagree the bytecode wins, and the disagreement is silent: a "fix"
that changes nothing, or a number wrong by a factor of a hundred.

Complements `prove-the-check-can-fail` — that skill asks whether your check would
catch the bug, this one asks whether the library does what its name implies.

## Procedure

1. **State the claim** in one sentence, with what changes if it is false. A claim that
   changes no decision is not worth the detour.

2. **Prefer observation.** If the behaviour can be triggered and measured, do that —
   it is cheaper and exercises the real path. Decompile only what running cannot
   reveal: a default you would have to override to see, a serialization shape, a
   branch not reachable from your inputs.

3. **Locate the artifact.**

   ```
   find ~/.gradle/caches/modules-2/files-2.1 -path '*<artifact>*' -name '*.jar' | grep -v sources
   ```

   A `-sources.jar` beside it is better than bytecode — read that and skip to step 5.
   For a Gradle plugin, the jar under `<plugin-id>/<version>/` holds the task classes.

4. **Inspect.**

   ```
   unzip -o -q <jar> '<pkg>/<Class>*'
   javap -p -c '<pkg>/<Class>.class'
   ```

   - **Defaults** live in `static {}` / `<clinit>`, as the constant pushed before the
     constructor call.
   - **Kotlin default arguments** live in the `$default` synthetic bridge, not the
     signature.
   - **Serialization shape** lives in the generated `$Companion`; look for the JSON
     configuration builder for whether nulls are written or omitted.
   - **Which branch a task takes** — decompile the top-level `…Kt` class holding the
     function, and read the conditional.

5. **Report the evidence, not the conclusion.** Quote the constant or the instruction.
   "The default is strict" is an assertion; `ThresholdValidator(0F)` at `<clinit>` is
   a fact someone else can check.

## Sharp edges

- **A name is not a type.** A field called `*_percentage` may hold a fraction of 1; a
  field called `*_count` may hold bytes. If a value's magnitude surprises you when you
  first see real data, that is the signal.
- **A no-op reads like a tightening.** Setting an option to a value that is already the
  default advertises a guarantee nobody added — worse than leaving it alone.
- **Version skew.** Decompile the version actually resolving in this build, not the
  newest in the cache. `./gradlew :app:dependencies` settles it.

## When to STOP

- **A version-matched sources jar, or the tagged source for that exact version,
  exists.** Read it — bytecode is the fallback, not the goal.
- **The claim does not change a decision.** Curiosity is not a trigger.
- **It is first-party code.** Read the source.
- **The class is obfuscated.** Say the claim is unverified rather than guessing from
  mangled names.
