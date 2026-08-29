# Skill Quality Evaluation

You are an expert in Claude Code skill design. Score the skill file below on five dimensions, then output **only** a single JSON object matching the schema at the bottom. No prose, no markdown, no preamble — JSON only.

A skill is a procedural recipe Claude loads when a trigger fires. Skills should fire only when relevant, then bundle a specific procedure with clear stopping conditions. This rubric reuses the standard 5-dimension scoring vocabulary, but with skill-specific definitions.

## Scoring Dimensions

Each dimension is scored 1–5.

### 1. Clarity (1–5) — Trigger specificity
Does the frontmatter `description` fire correctly *only* when it should?
- **5** — Trigger names specific user phrases / actions / artifact types. Hard to misfire.
- **3** — Trigger is partially specific; could spam on overlapping topics.
- **1** — Trigger is generic ("use when working with files") and would fire constantly.

### 2. Conciseness (1–5)
Is the SKILL.md free of bloat, restated material, and unnecessary preamble?
- **5** — Lean. Every line earns its place.
- **3** — Some padding or motivational text.
- **1** — Heavily padded; restates the same idea in multiple sections.

### 3. Completeness (1–5) — STOP coverage + procedure coverage
Does it cover the procedure's full happy path AND a representative set of stop conditions (auth issues, missing tools, shared state, ambiguous input, irreversible actions)?
- **5** — Procedure walks the full task; STOP section names ≥3 distinct edge cases.
- **3** — Procedure is mostly complete; STOP section is shallow (≤1 condition) or missing common edges.
- **1** — Procedure is partial OR no STOP section.

### 4. Consistency (1–5)
Are there contradictions inside the file? Does the procedure match what the trigger advertises? Are the stop conditions reachable from the procedure (not orphaned)?
- **5** — Fully consistent; procedure does what the description promises.
- **3** — Minor tensions (e.g. example shows command X, prose calls it Y).
- **1** — Procedure does not match the trigger, or STOP conditions reference steps that don't exist.

### 5. Actionability (1–5)
Can an AI agent execute the procedure verbatim, or does it require human judgment / out-of-band knowledge?
- **5** — Every step is a concrete tool invocation, code block, or decision rule with named inputs.
- **3** — Most steps are executable; one or two require human interpretation.
- **1** — Many steps are abstract ("evaluate quality", "use good judgment") with no decision rule.

## Grade Mapping

- 23–25 → **A**
- 20–22 → **B**
- 17–19 → **C**
- 14–16 → **D**
- below 14 → **F**

## Findings

List up to 5 specific issues. Each finding includes:
- `dimension` — which score it pulled down
- `file` — path of the skill file (e.g. `user-dev/skills/<name>/SKILL.md`)
- `section` — heading the issue lives under (`description`, `Procedure`, `When to STOP`, etc.) or `"-"` if global
- `issue` — short statement of the problem
- `recommendation` — specific fix

Skip findings entirely if the skill is already excellent.

## Output Schema

```json
{
  "date": "<ISO 8601>",
  "domain": "<skill-name>",
  "git_hash": "<short hash>",
  "scores": {
    "clarity":       <1-5>,
    "conciseness":   <1-5>,
    "completeness":  <1-5>,
    "consistency":   <1-5>,
    "actionability": <1-5>
  },
  "total": <sum>,
  "percentage": <round(total/25*100)>,
  "grade": "<A|B|C|D|F>",
  "findings": [
    {
      "dimension": "<one of the five>",
      "file": "<path>",
      "section": "<heading or '-'>",
      "issue": "<short problem statement>",
      "recommendation": "<specific fix>"
    }
  ]
}
```

---

## Skill to Evaluate

The skill file is provided below. Score it as a single artifact.
