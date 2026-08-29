---
name: audit-diagram-claims
description: >
  Use before ticking any "architecture updated" / "diagram updated" checkbox on a PR,
  and whenever a change alters a cadence, a pipeline stage, a guarantee, a count, or
  introduces a subsystem. Also fire when the user asks "did you check the diagram",
  "is the diagram stale", "isn't there a diagram change here", or points out a diagram
  was skipped. Do NOT fire for changes with no behavioural surface — typo fixes,
  test-only diffs, dependency bumps, formatting.
---

# Audit what the diagram claims

A diagram node is not a shape, it is a set of claims. "Did a box move?" can be
answered without opening the file, which is exactly why it keeps returning a
false negative — the shapes are stable while the words inside them rot.

Ask what each box *asserts*, and what the map does not mention at all.

## Procedure

0. **Find the diagram.** In priority order: the file the PR template or
   contributor guide names (`docs/architecture.md` is the common one), then
   `grep -rlE '```(mermaid|plantuml)|\.drawio|\.puml' --include='*.md' .`, then
   any `docs/*architect*`. More than one hit means auditing each.

1. **List every claim each node label makes.** Write them out; do not eyeball.
   Claims come in five shapes:

   | Shape | Example | Falsified by |
   |---|---|---|
   | Cadence | `weekly cron` | a schedule change |
   | Count | `8 channels`, `three inputs` | adding or retiring one |
   | Stage list | `pypdf → segment → parse` | inserting a stage |
   | Guarantee | `refuses to write if a slug would collide` | changing the failure mode |
   | Routing | `→ corpus_sentences` | re-pointing a sink |

2. **Check each claim against reality, not against your diff** — a label goes
   stale from someone else's merge as readily as your own. Read the cron, count
   the registry, open the function the guarantee names.

   **Include the prose next to the diagram** — the legend, the paragraphs under
   it, and any plain-words summary. They restate the same claims in words and
   rot independently; a summary saying "three inputs" under a diagram with four
   is a contradiction a reader hits before either is checked.

3. **Ask what is missing.** Enumerate the repo's units from the first of these
   that exists, then grep the diagram file for each name:

   ```bash
   ls -d */ ; ls .github/workflows/*.yml     # dirs, then scheduled jobs
   # else: the package/module manifest, or the README's structure section
   grep -i '<name>' <diagram-file>
   ```

   **Any name with zero hits is a reportable gap.** This is the strongest signal
   available, and the only one a code review cannot give you: nothing in a diff
   shows a subsystem that was never drawn.

4. **Prefer the smallest true edit.** If a claim is false, edit it to what is
   true today — unless the fix is already in flight, which means you can name it
   (`gh pr list --search '<subject>'`, or a branch that changes the file the
   claim describes). Name it or edit it; "someone is probably fixing that" is
   not a reason to leave a falsehood on the map.

5. **Render it before pushing, and prove the check can fail.** A broken diagram
   renders as an error block and is worse than a stale one. The requirement is
   that you *saw it render* — for anything that is not mermaid, or a repo with
   no node/npm, use whatever the host provides (the forge's preview, `plantuml
   -checkonly`, opening the `.drawio`) and say which you used. For mermaid in a
   node repo:

   ```bash
   npm install mermaid jsdom
   node --input-type=module -e '
     import fs from "node:fs"; import { JSDOM } from "jsdom";
     const d = new JSDOM("<!doctype html><body>");
     globalThis.window = d.window; globalThis.document = d.window.document;
     Object.defineProperty(globalThis, "navigator", { value: d.window.navigator, configurable: true });
     const { default: m } = await import("mermaid"); m.initialize({ startOnLoad: false });
     const src = fs.readFileSync(process.argv[1], "utf8");
     const blocks = [...src.matchAll(/```mermaid\n([\s\S]*?)```/g)].map(x => x[1]);
     let bad = 0;
     for (const [i, b] of blocks.entries())
       try { await m.parse(b); console.log(`block ${i+1}: OK`); }
       catch (e) { bad++; console.error(`block ${i+1}: ${String(e.message).split("\n")[0]}`); }
     process.exit(bad ? 1 : 0);
   ' <diagram-file>
   ```

   Then break it on purpose and confirm exit 1 — corrupt an **arrow**
   (`-->` → `--`), not a label. See the first sharp edge for why.

6. **Report the claims you verified**, not "diagram updated". "Checked cadence,
   count and the two guarantees; added the missing discovery node" is auditable.

## Sharp edges

- **A valid-looking mutation is not a test.** Inside a quoted mermaid label,
  `[[[` is legal text and parses fine — injecting it shows green and proves
  nothing. Break the edge syntax itself.
- **Guarantees rot first.** They are added by the PRs least likely to think
  about pictures — the ones hardening a failure path. Check them before cadences.

## When to STOP

- **No diagram file in the repo** — nothing to audit; say so.
- **The change has no behavioural surface.** Tick nothing and state why, rather
  than performing an audit to justify a checkbox.
- **The diagram belongs to another team** — report the stale claim, do not edit
  their file.
- **The rot is large.** If more than a handful of claims are false, the map
  needs its own PR; fixing it inside an unrelated change buries both.
