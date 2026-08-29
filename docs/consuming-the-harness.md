# Using the harness from another repo

Standalone, the harness manages its own config: the engine and the files it
scores are one checkout. That is the simple case and needs no configuration.

A **consumer repo** keeps its own config — its registries, its workspace domains,
its identity files — and vendors the harness to operate on them. One environment
variable makes the difference.

## The two roots

| Variable | Points at | Holds |
|---|---|---|
| `HARNESS_ROOT` | the engine checkout | `bin/`, `lib/`, `evals/prompts/`, `evals/eval-schema.json`, `config/templates/` |
| `REPO_ROOT` | the config repo being managed | `config/*.conf`, `user-dev/`, `user-pers/`, `workspace/`, `evals/results/`, `benchmarks/scores/` |

`HARNESS_ROOT` is derived from where `lib/common.sh` sits and is not
configurable. `REPO_ROOT` is `AGENT_CONFIG_ROOT` when that is set, and
`HARNESS_ROOT` otherwise.

An `AGENT_CONFIG_ROOT` that is not a directory is a hard error. Falling back to
the harness would quietly manage the wrong repo's config and report success.

## Setting it up

Vendor the harness — a submodule pins an exact commit, which is what you want:

```bash
git submodule add https://github.com/<owner>/agent-config-harness .harness
```

Then point every invocation at your repo. In a `Justfile`:

```make
export AGENT_CONFIG_ROOT := justfile_directory()

setup:
    @./.harness/bin/setup.sh

check:
    @./.harness/bin/check-health.sh

eval domain="all":
    @./.harness/evals/run-eval.sh {{domain}}
```

Your repo then holds only config:

```
config/domains.conf          your domains
config/marketplaces.conf     your skill marketplaces
user-dev/  user-pers/        your instruction files
workspace/<domain>/          your per-domain rules
.harness/                    the engine, pinned
```

## What this buys, and what it costs

The engine is versioned and tested once, in its own repo, with its own CI. Your
config repo stops carrying a copy of machinery it did not write, and updating the
engine becomes a submodule bump you can review.

The cost is a submodule, which is a real cost: a clone needs `--recurse-submodules`
(or a later `git submodule update --init`), and a stale pin is invisible until
something behaves oddly. If you would rather not, keeping the harness as your own
fork and merging from upstream is a legitimate alternative — the two-root split
below is what makes either work.

## Verifying the split

The failure mode is silent: if the override is ignored, the engine reads its own
example domains and reports everything healthy. Check explicitly:

```console
$ AGENT_CONFIG_ROOT=$(pwd) ./.harness/bin/check-health.sh
ℹ ── Domains ──
✔ domain 'your-domain' workspace: workspace/your-domain
```

If you see the harness's example domains — `mobile`, `web-react`, `backend-node`
— the override is not reaching the script.
