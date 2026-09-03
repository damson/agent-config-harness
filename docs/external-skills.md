# External skills

Some skill bundles are published by someone else and ship with their own
installer CLI. ai-setup **registers** those instead of copying them in:
`config/external-skills.conf` records how to install each one, and
`bin/install-external-skills.sh` runs it on request.

Installing is always optional. Nothing here is required for `just setup`,
`just check`, or the test suite to pass.

## What is registered

| Provider | Installs | Vendor CLI | Docs |
|---|---|---|---|
| `android-skills` | Google's Android skills (Compose, CameraX, Perfetto, Play policy, …) | `android` | [developer.android.com/studio/cli](https://developer.android.com/studio/cli) |
| `impeccable` | Design direction, critique and anti-pattern detection for frontend work | `npx` | [impeccable.style](https://impeccable.style) |

Getting the vendor CLI when a provider reports `tool-missing`: `npx` ships with
Node. The `android` CLI installs with
```bash
# Apple silicon; swap darwin_arm64 for darwin_x86_64 or linux_x86_64
curl -fsSL https://dl.google.com/android/cli/latest/darwin_arm64/install.sh | bash
```

Both install into `~/.claude/skills/` (and any other agent harness they detect:
`~/.gemini/skills/`, `~/.copilot/skills/`), so they resolve in every project on
that machine, not only in ai-setup. Plugins land elsewhere and are not
registered; see below.

## Commands

```bash
just skills-status      # what is installed, what is missing. Installs nothing
just skills-install     # prompt per provider (needs a terminal)
just skills-install --yes            # install everything missing, no prompts
just skills-install --only impeccable
```

`just setup` reports what is missing and stops there. It never prompts and never
installs; setup has to run unattended in CI.

**Running this without a terminal** (an agent, a script, CI): use `--yes` or
`--only`. The bare `just skills-install` form prompts, and with no TTY it
deliberately does nothing at all rather than guessing.

What happens when things go wrong:

| Situation | Behaviour |
|---|---|
| Vendor CLI not on `PATH` | Reported as `tool-missing`, skipped, exit 0 |
| Install command exits non-zero | Warns with the docs URL, continues to the next provider, exit 0 |
| `--only <unknown-id>` | Errors and exits non-zero, listing the registered ids |
| Probe path exists | Counted as installed, **even if the install is stale or partial**. The script has no version check; repair or upgrade with the vendor CLI (see [Refreshing](#refreshing)) |

The probe is why `--yes` is safe to repeat. It is also why this script cannot add
a *new* skill from a provider you already have: the probe path is already there,
so the provider is skipped. Run the vendor CLI directly for that.

## Plugins are a different mechanism, and are not registered here

`config/external-skills.conf` cannot express a Claude Code **plugin**, and the
reason is worth knowing before you try.

Installed plugins are recorded in `~/.claude/settings.json` under
`enabledPlugins`, not on disk. The registry's `<probe>` is a path-existence
check (`[ -e "$probe" ]`), so it has nothing truthful to point at:

| Path | After `marketplace add` | After `install` | After `uninstall` |
|---|---|---|---|
| `~/.claude/plugins/marketplaces/<name>` | created | | **survives** |
| `~/.claude/plugins/cache/<name>/<name>` | | created | **survives** |

Both paths outlive an uninstall (verified 2026-08-29). A registry line would
therefore report the plugin as installed forever after the first install, and
`just skills-status` would show a green that means nothing: the failure mode
this repo works hardest to avoid.

Install a plugin by hand, and record it here:

### `i-have-adhd`

Shapes output for a reader with ADHD: action first, numbered steps, no
preamble or recap. Source: [github.com/ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd).

```bash
claude plugin marketplace add ayghri/i-have-adhd
claude plugin install i-have-adhd@i-have-adhd --yes
```

Both commands are idempotent and exit `0` on a re-run. `--yes` is required
when stdout is not a TTY.

The skill sets `disable-model-invocation: true`, so it only fires on
`/i-have-adhd`. For always-on, create `~/.claude/.i-have-adhd-always`; its
`SessionStart` hook then injects the full ruleset on every
startup/resume/clear/compact. That flag file is **not** tracked here, so a
fresh machine will not have it.

Where its rules meet this repo's own output rules (the verdict budget, the
one-row-per-finding PR reply), the reconciliation is in `user-dev/CLAUDE.md`
under "With `i-have-adhd` active". It lives there rather than in the skill
because the plugin is overwritten on update, and user instructions already
outrank skills.

## Why these are not vendored into `user-dev/skills/`

- **They update themselves.** `android skills add` and `npx impeccable update`
  fetch the current version. A copy in git is a snapshot that goes stale silently.
- **They fail the authored-skill bar.** `tests/skills.bats` requires a
  `## Procedure` (or `## Step N`) and a `## When to STOP` heading in every
  `SKILL.md` under `user-dev/skills/`. None of the 22 Android skills carry both.
  Committing them means either a red CI or a weakened test.
- **They would distort the benchmark.** `just eval-skills all` scores every
  skill in that directory. Scoring someone else's writing tells us nothing about
  ours and moves the trend line for the wrong reason.
- **They are large.** The two providers together are roughly 8 MB of vendored
  reference material.

The trade is reproducibility: a clone gets the *instructions* to reach the same
state, not the state itself, and versions can differ between machines. That is
the right trade for a bundle with its own update channel.

## Refreshing

The registry installs; it does not upgrade. Use the vendor CLI:

```bash
android skills list          # installed and available
android skills add --all     # add anything new
android skills add <id>      # add one
npx impeccable check         # is a newer version published?
npx impeccable update
```

## Adding a provider

Append one line to `config/external-skills.conf`.

```
<id> = <requires> :: <probe> :: <install> :: <docs>
```

The id is split off on the first `=`; the rest splits on `::`. Whitespace around
every separator is stripped, so align the columns however you like. A field
cannot itself contain `::`; the install command is the only field likely to
want one, and there is no escape.

A filled-in line, for the shape of each field:

```
impeccable = npx :: ~/.claude/skills/impeccable :: npx --yes impeccable@latest install --global --yes :: https://impeccable.style
```

| Field | Meaning |
|---|---|
| `<id>` | Name used by `--only` and shown in `just skills-status` |
| `<requires>` | Command that must be on `PATH`. Absent means skip and print `<docs>`, never an error |
| `<probe>` | Path that exists once installed. Drives idempotence; a leading `~` expands |
| `<install>` | Run verbatim |
| `<docs>` | Where to read about the provider and how to get `<requires>` |

Prove the line works before committing it. Closing stdin is the check: an
installer that wants input fails here instead of hanging on someone else's
machine, which is the one failure the registry hides until it reaches them.
`--help` is not a safe way to probe first: `npx impeccable install --help` runs
the install rather than printing usage. Probe in a scratch directory.

```bash
./bin/install-external-skills.sh --only <id> --yes </dev/null
just skills-status        # the new provider now reports as installed
bats tests/external-skills.bats
```

## Removing one

Dropping the registry line stops ai-setup offering the provider; it does not
uninstall anything. Remove the installed bundle with its own CLI:
`android skills remove <id>`, or delete `~/.claude/skills/impeccable`.

Delete only what the vendor installed. `~/.claude/skills/` also holds the
symlinks `just setup` creates for `user-dev/skills/`; the vendor entries are the
real directories beside them (`find ~/.claude/skills -maxdepth 1 -type d`).

## The impeccable design hook

Installing the impeccable *skill* is global. Its *design detector hook* is not:
it is wired per project, and for Claude Code it lands in
`.claude/settings.local.json`, which is gitignored by design. Run this once in
each website project, on each machine:

```bash
npx impeccable install     # in the project root
```

A teammate who clones that project has the skill but no hook until they run it
too. `workspace/web-react/CLAUDE.md` carries this as a working rule.

`just impeccable-hooks` does this across projects instead of one at a time:

```bash
just impeccable-hooks --list     # which frontend projects have the hook
just impeccable-hooks            # prompt per project, install the missing ones
just impeccable-hooks <path>     # just this one
```

"Frontend project" is not a hardcoded list. A domain qualifies when **its own
`CLAUDE.md` mentions impeccable**, and its projects are the git repos directly under
`~/<workspace-path>` for each path the domain registers. Adding the rule to another
domain's guide brings that domain in with no change here.

The recipe never installs unattended: with no TTY and no `--yes` it reports and exits,
so `just setup` and CI stay side-effect-free.

`/impeccable init` still has to be run once per project **inside a session**; it is a
slash command and writes the `PRODUCT.md` / `DESIGN.md` brief, so it cannot be
scripted from here. The recipe says so after installing.

