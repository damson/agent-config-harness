# Contributing

Hi, and thanks for being here! 👋 Every issue and PR gets read, and small
contributions count just as much as big ones: a sharpened sentence in a doc
is as welcome as a new check. One honest caveat: this project is maintained by
one person, so replies can take a few days. It's not disinterest, it's a queue.

## Ways to contribute

- **Report something confusing.** If a script's output or a doc left you
  guessing, that's a bug in the project, not in you; open an issue and say
  where you got lost.
- **Bring a hard-won rule.** The linters and validators here grew one painful
  lesson at a time; if a config mistake bit you somewhere else, a check that
  catches it belongs here.
- **Add a worked example.** The docs teach by transcript: a real run from
  your own setup is worth more than a paragraph of theory.
- **Fix a typo, tighten a sentence.** Genuinely welcome, no issue required.

## Before you open a PR

```bash
just test     # bats suite; must pass
just lint     # secret scan
just check    # every link and domain resolves
```

Shell is linted the way CI lints it:

```bash
shellcheck -x -S warning -e SC1091 bin/*.sh evals/*.sh benchmarks/*.sh lib/*.sh
```

## The rules that are actually enforced

- **Adding a domain is a one-line change** to `config/domains.conf`. A PR that
  hardcodes a domain name in a script will be asked to use the registry instead.
- **A new skill needs** frontmatter `name:` matching its folder, a `## Procedure`
  (or `## Step N`) heading, and a `## When to STOP` section. Three tests check this.
- **Skills must be portable.** Never name this repo's paths or assume its folder
  layout. A skill is installed into other people's environments.
- **`AGENTS.md` beside a domain's `CLAUDE.md` is a symlink.** Do not convert it
  to a real file.

## Changing behaviour

If you change a script, add or update a `bats` case, and make sure you have seen
it fail. A test that has only ever been green is not evidence: break the thing
it covers, watch it go red, then fix it. Several tests in this repo carry a
comment saying exactly what mutation they were proven against.

## Eval scores

`just eval` needs the Claude CLI and an API key, so most contributors cannot run
it. That is fine; it is not required for a PR. If you are changing a config file
and can run it, include the before and after scores. Remember the score moves
±1–2 on borderline runs; one run is not a trend.

## Releases and changelog

Gitflow: `develop` integrates, `main` releases, and `main` only moves by
promoting `develop` through the standing release PR (`just release` opens or
refreshes it; merging stays a human decision). Each release is tagged `vX.Y.Z`
with a GitHub Release whose notes are the changelog, and the `v1` tag moves to
the latest `v1.x.y` so Action consumers pinned to `@v1` pick up fixes.

The post-merge steps are manual today, run by a maintainer against the merge
commit on `main`:

```bash
gh release create vX.Y.Z --target main --title "vX.Y.Z" --notes "<changelog>"
git fetch origin main && git tag -f v1 origin/main && git push -f origin v1
```

(`gh release create` makes the `vX.Y.Z` tag itself; only `v1` moves by hand.)

There is no `CHANGELOG.md`, deliberately: the release PR carries the full
inventory of what ships, and the GitHub Release keeps it.
