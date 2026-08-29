# Global agent instructions

<!--
    YOUR global rules, loaded in every project. `bin/setup.sh` symlinks this to
    ~/.claude/CLAUDE.md. Domain-specific rules live in workspace/<domain>/CLAUDE.md
    and are picked up automatically when you are working in that domain.

    Replace everything below with your own. What is here is a skeleton showing
    the shape that scores well — see docs/evaluation.md for the rubric.

    THE ONE RULE WORTH KEEPING: this file loads EVERY session. Keep it under
    ~100 lines. Procedures, command references and rationale belong in docs/;
    reference them, never restate them. Before adding a line, ask whether it is
    needed at READ time or only at DO time. Only read-time rules belong here.
-->

## Git

- One focused, logical change per commit.
- Cut feature branches from the integration branch, not from a stale local base.

## Communication

- Be concise. Skip preamble.
- Lead with the recommendation, then the reason.
- Confirm before anything risky or irreversible.

## Config authoring

**This file is an entry point, not a manual.** Keep it to what the project is,
the workflow, a task → doc routing table, and the rules that cause damage before
you would think to open a doc.

`@path` imports work in `CLAUDE.md` but **not** in `.claude/rules/` files, and
they do not reduce context — an imported file is expanded at launch. To share a
rule between locations, symlink it. Tested, with controls: `docs/claude-md-loading.md`.
