# Skill marketplaces

Skills used to be vendored into this repo. Any skill that is genuinely portable
now lives in a **Claude Code marketplace** instead: one copy, versioned by its
publisher, installable by theme. What stays here is the machinery: a registry
so the set is reproducible, and the checks that hold someone else's skills to the
same standard as your own.

`config/marketplaces.conf` records which marketplaces and which plugins, so a
fresh machine ends up with the same skills rather than whatever was remembered.

## The registry

```
<id> = <source> :: <plugins> :: <docs>
```

```
hard-won-skills = damson/hard-won-skills :: * :: https://github.com/damson/hard-won-skills
```

| Field | Meaning |
|---|---|
| `<id>` | The **marketplace** name, from its `marketplace.json` `name` field |
| `<source>` | Anything `claude plugin marketplace add` takes: `owner/repo`, a git URL, a local path |
| `<plugins>` | Comma-separated plugin names, or `*` for every plugin the marketplace declares |
| `<docs>` | Where to read about it |

**The id is not the repository name.** They are allowed to differ, and here they
happen to match only because the repo was renamed to agree with the manifest.
`plugin@marketplace` addresses the *marketplace* name, so a mismatch produces a
confusing "plugin not found" against a marketplace that is clearly present.

Adding one is a one-line change. No script reads a marketplace name directly.

## Commands

```bash
just marketplaces-status              # what is registered, and what is installed
just marketplaces-install             # add every marketplace, install its plugins
just marketplaces-install <id>        # just one
just validate-marketplace <id>        # structural check on the skills it installed
just eval-marketplace <id> [plugin]   # score those skills on the skill rubric
just validate-skills [dir]            # structural check on any skills tree
```

Worked example, from nothing to scored:

```console
$ just marketplaces-status
ℹ marketplace: hard-won-skills  (damson/hard-won-skills)
⚠   not added yet — run 'just marketplaces-install'
ℹ   docs: https://github.com/damson/hard-won-skills

$ just marketplaces-install
ℹ Adding marketplace hard-won-skills
✔   installed git-workflow
✔   installed agent-config
✔   installed verification
✔   installed data-safety
✔   installed mobile-ui

$ just validate-marketplace hard-won-skills
✔ 31 skill(s) in marketplace 'hard-won-skills' pass all structural checks

$ just eval-marketplace hard-won-skills verification
ℹ ── hard-won-skills/verification ──
ℹ Scoring skill: prove-the-check-can-fail
ℹ   Total: 24/25  Grade: A
```

`just setup` never installs marketplaces. Setup has to run unattended and adding
a marketplace clones from the network, so it stays an explicit step.

## Validating skills you did not write

A marketplace hands you skills from someone else, held to no standard on the way
in. `bin/validate-skills.sh` applies the four invariants this repo enforces on
its own skills to any tree:

| Check | Why it is not cosmetic |
|---|---|
| frontmatter `name:` matches the folder | A mismatch makes the skill unaddressable |
| `description:` is non-empty | The description is the whole trigger; an empty one never fires |
| a `## Procedure` or `## Step N` section | Without steps it is an essay, not a skill |
| a `## When to STOP` section | This is what stops a skill firing on work it should decline |
| leaf names unique across groups | Skills install **flat**; a duplicate silently shadows another |

It reports every problem rather than stopping at the first, and exits non-zero if
any skill fails.

Point it anywhere:

```bash
just validate-skills                          # this repo's own skills
just validate-skills ~/some/other/skills      # any tree
just validate-marketplace hard-won-skills    # every plugin a marketplace installed
```

## Scoring skills you did not write

`SKILLS_DIR` points the eval harness at a tree this repo does not own:

```bash
SKILLS_DIR=~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills \
  ./evals/run-skill-eval.sh
```

`just eval-marketplace` resolves that path for you. Remember the eval moves ±1–2
on borderline scores; the same skill can come back A on one run and B on the
next, so a single run is not a trend.

## Why status asks the CLI instead of checking a path

The obvious implementation is a path probe, the way `config/external-skills.conf`
works. It is wrong here, and quietly:

| Path | After `marketplace add` | After `install` | After `uninstall` |
|---|---|---|---|
| `~/.claude/plugins/marketplaces/<id>` | created | | **survives** |
| `~/.claude/plugins/cache/<id>/<plugin>` | | created | **survives** |

Both outlive an uninstall (verified). A path probe would report every plugin as
installed forever after the first install, a green that means nothing. Installed
state lives in Claude Code's `settings.json`, so `marketplaces.sh` asks
`claude plugin list` instead.

## The collision to know about

If a skill exists **both** in `user-dev/skills/` and in an installed marketplace
plugin, you get two copies in `~/.claude/skills/` under the same leaf name: one
symlinked by `just setup`, one from the plugin. They shadow each other and which
one wins is not something you want to reason about.

Keep each skill in exactly one place. A skill that would work in any repo belongs
in the marketplace; `user-dev/skills/` is for skills coupled to this repo's own
tooling.
