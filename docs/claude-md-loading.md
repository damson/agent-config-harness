# How instruction files load, and what that rules out

Tested against Claude Code on 2026-08-17, each claim with a control. Written down
because two of these are the opposite of what the shape of the feature suggests, and
both were about to drive a design decision.

## `@import` works in CLAUDE.md, not in rules files

`CLAUDE.md` supports `@path/to/file`. Relative and absolute paths both work, relative
resolving against the file containing the import, nesting up to four hops. Parsing
skips code spans and fenced blocks, so `` `@README` `` in backticks stays literal.

A `.claude/rules/*.md` file does **not** expand `@path`. It looks like it should (same
markdown, same load-at-launch behaviour) but the import is passed through as text.

How that was established, because "it didn't work" and "the file never loaded" look
identical from outside:

| Setup | Result |
|---|---|
| `.claude/rules/brief.md` containing `@secret-brief.md` | value not visible |
| **Control:** same rule file with the value written inline | value visible |
| `.claude/rules/web.md` as a **symlink** to a file outside the project | value visible |

The control is what makes the first row mean anything: the rule file loads fine, so
the import specifically is what does not expand.

## Imports do not save context

Splitting a large `CLAUDE.md` into `@` imports organises it but does not shrink what
loads: imported files are expanded into context at launch. If the goal is a smaller
context, imports are the wrong tool.

## Path-scoped rules are the tool that does

`.claude/rules/*.md` accept `paths:` frontmatter (glob list). Those rules load **only
when Claude touches a matching file**, so a repo spanning several stacks can carry a
guide per stack and pay for each only in the files it covers.

Combined with the symlink result above, that gives composition without duplication:
symlink each shared guide into `.claude/rules/`, and scope it with `paths:`. The
frontmatter has to live in the file itself, which is the open question when the same
file is also served as a project `CLAUDE.md`.

## Load order and lifetime

- Files **above** the working directory load in full at launch, root-most first, so the
  nearest file is read last. Files in subdirectories load on demand.
- `CLAUDE.local.md` is appended after `CLAUDE.md` at each level.
- Everything loads **at session start**. A running session does not pick up an edit;
  restart it.
- A project-root `CLAUDE.md` is re-injected after `/compact`. Nested files and
  path-scoped rules are not; they reload when a matching file is next read.
