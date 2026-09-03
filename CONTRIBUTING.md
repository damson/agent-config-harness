# Contributing

Maintained by one person. Issues and PRs are welcome and may be slow.

## Before you open a PR

```bash
just test     # bats suite — must pass
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
- **Skills must be portable** — never name this repo's paths or assume its folder
  layout. A skill is installed into other people's environments.
- **`AGENTS.md` beside a domain's `CLAUDE.md` is a symlink.** Do not convert it
  to a real file.

## Changing behaviour

If you change a script, add or update a `bats` case, and make sure you have seen
it fail. A test that has only ever been green is not evidence — break the thing
it covers, watch it go red, then fix it. Several tests in this repo carry a
comment saying exactly what mutation they were proven against.

## Eval scores

`just eval` needs the Claude CLI and an API key, so most contributors cannot run
it. That is fine — it is not required for a PR. If you are changing a config file
and can run it, include the before and after scores. Remember the score moves
±1–2 on borderline runs; one run is not a trend.

## Releases and changelog

Gitflow: `develop` integrates, `main` releases — and `main` only moves by
promoting `develop` through the standing release PR (`just release` opens or
refreshes it; merging stays a human decision). Each release is tagged `vX.Y.Z`
with a GitHub Release whose notes are the changelog, and the `v1` tag moves to
the latest `v1.x.y` so Action consumers pinned to `@v1` pick up fixes.

There is no `CHANGELOG.md`, deliberately — the release PR carries the full
inventory of what ships, and the GitHub Release keeps it.
