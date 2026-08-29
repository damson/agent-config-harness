# agent-config-harness

**Agent instruction files, scored and regression-tested like code.**

`CLAUDE.md`, `AGENTS.md`, `.cursorrules` and skill definitions steer how coding
agents behave, and they are usually maintained the way prompts are maintained:
edited by feel, never measured, quietly rotting. This repo treats them as
something you can grade, track, and break a build over.

```
$ just eval backend-node
ℹ Scoring domain: backend-node
✔ Result written: evals/results/2026-08-29-backend-node.json
ℹ   Total: 24/25  Grade: A
ℹ   Findings (5):
    - [completeness] No build/run/verify commands. An agent cannot tell how to
      install, typecheck, lint or run the test suite before claiming a change works.
    - [clarity] Logging: `requestId` propagation is required but the mechanism is
      unspecified — AsyncLocalStorage vs an explicit context argument produces
      very different code.
    …
```

That is a real run against the example domain in this repo, not an illustration.

Three things make that possible, and they are the reason this exists:

| | |
|---|---|
| **A rubric with a number** | Config files are scored 1–5 on clarity, conciseness, completeness, consistency and actionability. Out of 25, with a letter grade and specific findings — not a vibe. |
| **A trend, not a snapshot** | Scores are recorded per domain over time, so you can tell an improvement from a rewrite that felt productive. |
| **Structural tests** | A `bats` suite enforces the invariants a rubric cannot see: skill frontmatter matching its folder, required headings, unique names across a flat install namespace, no symlink silently turned back into a duplicate file. |

**Requires an API key.** The eval harness shells out to the Claude CLI. Everything
else — linking, health checks, the test suite — runs offline. If you only want the
structure and the tests, you never need a key.

---

## Install

```bash
git clone <this repo> ~/workspace/agent-config-harness
cd ~/workspace/agent-config-harness
just setup      # symlink configs and skills into ~/.claude/, install git hooks
just check      # verify every link and domain resolves
just test       # the bats suite
```

`just setup` is idempotent and unattended: it never prompts and never installs
third-party software. Run it from the primary checkout, not from a git worktree —
it points every skill symlink at the repo root, and a worktree path dies with the
worktree.

## The idea: domains

A **domain** is a kind of project — mobile, backend, frontend, data. Each one owns
a config file, and the registry says where it lives and what is managed:

```
# config/domains.conf
mobile      = workspace/mobile   : AGENTS.md>project/CLAUDE.md, CLAUDE.md, .cursorrules
web-react   = workspace/web-react, workspace/web : CLAUDE.md
```

Adding a domain means appending one line. No script reads a hardcoded path;
everything goes through the registry via `lib/common.sh`.

`CLAUDE.md` is the single source of truth per domain. The `AGENTS.md` beside it is
a **symlink**, so tools that read one or the other resolve identical content and
cannot drift. Turning that symlink back into a real file is the most common way
to tank a domain's score, and the test suite fails when it happens.

The `A > B` syntax maps a file the project calls `A` to `B` inside this repo — for
when a project's `AGENTS.md` is your `project/CLAUDE.md`.

## Layers

```
user-pers/        identity — who you are, how the agent writes as you
user-dev/         your global rules + your skills, loaded in every project
workspace/<d>/    per-domain rules, loaded when you work in that domain
  project/        the layer a whole team agrees, kept separate from yours
```

The split matters because the layers have different owners and different
lifetimes. Your commit-message preference is not your team's architecture rule,
and mixing them makes both harder to change.

## Commands

| Command | What it does |
|---|---|
| `just setup` | Link configs and skills globally; install git aliases and pre-push hook |
| `just check` | Health-check every link and registered domain |
| `just test` | Full `bats` suite |
| `just lint` | Scan for secret value patterns |
| `just eval [domain]` | Score config quality. Needs the Claude CLI |
| `just eval-skills [skill]` | Score a skill against the skill rubric |
| `just benchmark` | Print the score trend per domain |
| `just skills-install` | Install third-party skill bundles from the registry |
| `just release` / `just backmerge` | Open the release and back-merge PRs. Never merges |

## Skills

The skills this repo produced live in a separate marketplace, grouped by theme —
see `agent-skills`. What stays here is the **machinery that holds a skill to a
standard**, plus one skill (`refresh-domain-benchmark`) that is coupled to this
repo's own eval harness and makes no sense outside it.

`tests/skills.bats` enforces, for every skill under `user-dev/skills/`:

- frontmatter `name:` matches the folder name
- a non-empty `description:`
- a `## Procedure` (or `## Step N`) heading
- a **`## When to STOP`** section
- leaf names unique across grouped folders, because skills install *flat* into
  `~/.claude/skills/` and share one namespace

`just eval-skills <name>` then scores the skill's prose on the same rubric the
config files get.

## What this is not

- **Not a prompt library.** It is the machinery for maintaining your own.
- **Not a Claude-only tool**, though that is what it is tested against. The
  symlinked `AGENTS.md` layer exists so other harnesses resolve the same content.
- **Not turnkey.** The domains shipped here are examples with real structure and
  placeholder content. Replace them; the tests will tell you when you have broken
  something.

## Documentation

- [Architecture](docs/architecture.md) — the four layers in depth
- [Evaluation](docs/evaluation.md) — the rubric and how to read a score
- [Git flow](docs/git-flow.md) — branch model, release and back-merge PRs
- [External skills](docs/external-skills.md) — registering third-party bundles rather than vendoring them

General engineering notes that used to live here — how instruction files load,
shell and CLI traps, git syntax — moved to `engineering-notes`, since they are
reference material with a different lifetime than this repo.

## Support

Maintained by one person for one person's setup, published because the measurement
idea seemed worth sharing. Issues and PRs are welcome and may be slow. Bug reports
involving `just eval` are hard to reproduce without your config and your API key —
include the generated JSON from `evals/results/` and it becomes tractable.

MIT licensed.
