---
name: claude-md-pointer-check
description: >
  Use before creating or substantially editing any CLAUDE.md file. Detects
  when a sibling AGENTS.md or README.md already covers the planned content,
  and rewrites the CLAUDE.md as a pointer + Claude-only delta instead of a
  duplicate. Prevents the "byte-for-byte duplicate" anti-pattern the eval
  system penalizes on conciseness and consistency.
---

# CLAUDE.md pointer check

CLAUDE.md should rarely hold canonical content. Correct shapes:

| Context | Correct CLAUDE.md |
|---|---|
| Sibling `AGENTS.md` exists | One-line pointer: `See [AGENTS.md](AGENTS.md) — the same instructions apply to Claude.` |
| Project `README.md` covers commands + architecture | Pointer to README + only Claude-specific behavioral directives (self-modification rules, evaluator quirks, agent-only conventions) |
| Greenfield, no siblings | Write CLAUDE.md normally |

## Procedure

### 1. Identify siblings

In the same directory:
- `AGENTS.md` (canonical agent-instructions file)
- `README.md` (human-facing project docs, only relevant at project root)

If neither exists, this skill does not apply — write CLAUDE.md normally and
exit.

### 2. Compare planned content to siblings

For each section of the planned CLAUDE.md:

| Planned section overlaps with | Action |
|---|---|
| AGENTS.md (any sibling) | Drop the section — it belongs in AGENTS.md or is already there |
| README.md (commands, architecture, mental model) | Drop the section — defer to README |
| Neither (Claude-only directive) | Keep |

Examples of legitimate Claude-only directives:
- "`.claude/settings.json` cannot be auto-written from this repo"
- "Evaluator non-determinism ±1–2 — don't claim a trend from a single run"
- "When adding a domain, edit `config/domains.conf` only — never touch scripts"
  (a Claude-behavior rule the human reader of README doesn't need)
- "Never push to `main`; use the pre-installed hook + `bin/sync-back.sh`"

Examples of content that belongs **elsewhere**:
- Build/test commands → README
- Architecture diagrams → README
- Coding conventions → AGENTS.md
- Git commit format → AGENTS.md (or global preferences)

### 3. Apply the rewrite rule

Count the H2 / H3 sections of the planned CLAUDE.md. If at least half of them
were marked "drop" in step 2, rewrite the whole file as a pointer:

```markdown
# CLAUDE.md

See [AGENTS.md](AGENTS.md) — the same instructions apply to Claude.
```

or

```markdown
# CLAUDE.md — <project>

Read [README.md](README.md) first — it covers commands, architecture, and
git flow. The directives below are Claude-only and don't belong in README.

## Claude-only directives

- ...
- ...
```

### 4. Lint sibling for subjective phrasing

While here, scan the sibling AGENTS.md / README for phrases the eval system
flags as not-actionable:
- "leave it better than you found it"
- "stay scoped"
- "focus on core business logic"
- "keep it small / light / thin" (without a measurable bound)
- "alert" / "loud" (without a mechanism)

If found, surface each match inline (file path + line number + the problem
phrase) and propose a concrete replacement as a unified diff. The fix probably
belongs in the sibling, not this file — ask the user before editing the sibling.

## When to STOP

- **No sibling `AGENTS.md` or `README.md`** → skill does not apply; write
  CLAUDE.md normally.
- **User has explicitly asked for a standalone CLAUDE.md** (e.g. a repo where
  Claude is the only consumer and there's no AGENTS.md by design) → write
  normally; surface this skill's rationale once and continue.
- **Existing CLAUDE.md is already a pointer** → exit; nothing to do.
- **The duplication is deliberate** (e.g. an offline deployment that can't
  follow links) → flag once, then defer to user.
