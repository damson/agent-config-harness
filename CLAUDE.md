# CLAUDE.md — agent-config-harness

Read [README.md](README.md) first — it covers the commands, the layers, the
domain registry and what this repo is for. Don't duplicate that here.

## Claude-only directives

- **Adding a domain:** edit `config/domains.conf` only — never modify scripts.
  All tooling reads the registry through `lib/common.sh`.
- **Adding a third-party skill bundle:** edit `config/external-skills.conf` only
  — never copy it into `user-dev/skills/`, which is authored skills that
  `tests/skills.bats` and `just eval-skills` both hold to a standard a vendored
  bundle will fail. See [docs/external-skills.md](docs/external-skills.md).
- **`workspace/<domain>/CLAUDE.md` is the single source of truth; the `AGENTS.md`
  beside it is a symlink to it.** Edit `CLAUDE.md`; never turn a symlinked
  sibling back into a real file — that reintroduces the duplication that tanks
  `conciseness` and `consistency` in `just eval`. A `.cursorrules` stays a real
  file only when it carries content the `CLAUDE.md` does not.
- **Eval is non-deterministic by ±1–2 on borderline scores.** Don't claim a trend
  from a single run — re-run or compare averages.
- **`just eval-skills` writes `.json` on success and `-RAW.txt` only when the
  reply held no parsable object.** Read whichever artifact is *newest* and check
  its mtime — grepping the newest RAW after a successful run returns a previous
  run's score.
- **The eval's `consistency` dimension cannot tell disclosure from
  contradiction.** A skill that documents an unresolved dispute scores below one
  that silently asserts a side. State the trade-off; don't degrade the skill to
  chase the number.
- **New `SKILL.md` needs a `## Procedure` (or `## Step N`) heading AND a
  `## When to STOP` heading, and frontmatter `name:` = folder name** —
  `tests/skills.bats` enforces all three.
- **Skills must be portable.** A `SKILL.md` is installed into arbitrary
  environments, so it must never name this repo's paths (`user-dev/…`,
  `workspace/<domain>/…`) or assume its folder names. Say "the repo's config
  file", not the path it has here.
- **Project-specific skills are grouped and prefixed:**
  `user-dev/skills/<project>/<project>-<skill>/`. They still install flat, so
  leaf names are a shared namespace and must be unique. Generic skills stay at
  the top level and must not name a project.
- **Portable skills do not live here.** They belong in the themed marketplace
  repo. `user-dev/skills/` keeps only skills coupled to this repo's own harness —
  today that is `refresh-domain-benchmark`, which drives `evals/run-eval.sh` and
  reads `config/domains.conf`. A skill that would work anywhere is a sign it
  should be published to the marketplace instead.
- **Adding a skill marketplace:** edit `config/marketplaces.conf` only — never
  modify scripts. `bin/marketplaces.sh` reads it through `lib/common.sh`. The id
  is the marketplace's `name` from its `marketplace.json`, which need NOT equal
  the repo name; `plugin@marketplace` addresses the former.
- **Never probe a path to decide whether a plugin is installed.** Both
  `plugins/marketplaces/<id>` and `plugins/cache/<id>/<plugin>` survive an
  uninstall, so a probe reports installed forever. Ask `claude plugin list`.
  See [docs/marketplaces.md](docs/marketplaces.md).
- **Never run `bin/setup.sh` from a worktree.** It points every
  `~/.claude/skills/*` symlink at `$REPO_ROOT`, so a worktree run repoints them
  all at a path that dies with the worktree. Verify setup.sh edits with
  `bats tests/setup.bats` (isolated `$HOME`); run `just setup` from the primary
  checkout.
- **Never push to `main` or `develop`.** A pre-push hook blocks both. Branch off
  `develop` and PR back into it; `main` moves only by promoting `develop`.
- **CodeRabbit reads `.coderabbit.yaml` from the PR head branch** — the only
  resolution its docs establish. A config change merged to `develop` affects a
  review only once the PR's head contains that commit, i.e. branches cut or
  updated after the merge; older branches keep the config they carry.
- **The domains under `workspace/` are examples.** They carry real structure and
  placeholder content so the test suite and the eval harness have something to
  work on. Improving them as examples is fine; treating them as one person's
  real config is not.
- **Statusline doc stays in sync.** Any change to `user-dev/statusline.sh`
  (segments, order, colours, formatting, fields) must update the "Statusline"
  section in `README.md` in the same change.
- **Two roots, and they are not interchangeable.** `HARNESS_ROOT` is this
  checkout — scripts, rubrics, templates. `REPO_ROOT` is the config repo being
  managed, which is this one only when `AGENT_CONFIG_ROOT` is unset. A new path
  belongs to whichever owns the file: a rubric is `HARNESS_ROOT`, a domain's
  `CLAUDE.md` is `REPO_ROOT`. Getting it backwards is silent — the engine reads
  its own example domains and reports healthy.
