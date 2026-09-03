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

## In CI, if your harness fork is private

The harness itself is public, so the default case is one line — `submodules:
true` on `actions/checkout` and the pin resolves with no credentials at all.
Skip this section unless you maintain a **private fork** of the harness.

For a private fork: `actions/checkout` authenticates with the job's
`GITHUB_TOKEN`, which is scoped to the repo being built. A private fork lives
in a *different* repo, so the submodule fetch fails no matter what
`submodules:` is set to. Give the job a PAT with read access to the fork and
check the submodule out yourself:

```yaml
- uses: actions/checkout@v4          # no submodules: — it cannot reach the harness
  with:
    # The default persisted GITHUB_TOKEN header would stack with the one
    # below — http.extraheader is multi-valued — and GitHub rejects the
    # doubled Authorization. Turn it off; nothing later needs it.
    persist-credentials: false
- name: Check out the harness
  env:
    HARNESS_TOKEN: ${{ secrets.HARNESS_TOKEN }}
  run: |
    auth=$(printf 'x-access-token:%s' "$HARNESS_TOKEN" | base64 | tr -d '\n')
    git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $auth" \
      submodule update --init --depth 1 .harness
```

The `-c` scopes the credential to that one command on purpose. Writing it with
`git config --global` also works, but on a self-hosted runner the global config
persists across jobs — the auth header stays behind for whatever runs next, so
that route needs an explicit `git config --global --unset` in an `if: always()`
cleanup step.

Two things about that snippet are not obvious, and both cost real time.

**The credentials go in a header, not the URL.** The form everyone reaches for
first is rejected outright:

```bash
# Rejected by GitHub, whatever the token:
git clone https://x-access-token:$TOKEN@github.com/owner/repo.git
# remote: Invalid username or token. Password authentication is not supported
# for Git operations.
```

The error names a username and a password, so it reads as a credential-format
problem. It is not: GitHub refuses URL-embedded credentials for git operations
outright, and no token value makes that form work. The `http.extraheader` form
above is what `actions/checkout` itself uses.

**Storing the secret without a terminal stores nothing.** Set it like this:

```bash
read -rs TOKEN && printf '%s' "$TOKEN" | gh secret set HARNESS_TOKEN --repo <owner>/<repo>
```

Run interactively, `gh secret set NAME` prompts for the value. Run anywhere
without a TTY — a script, a CI step, an agent shell — it reads **stdin instead of
prompting**, and an empty stdin stores an **empty secret**. It exits `0` and the
secret listing shows the name with a fresh timestamp, so the only symptom is the
submodule checkout failing later with an ordinary `401`, indistinguishable from a
token that is invalid or revoked.

`read -rs` keeps the value off the screen and out of shell history, and piping it
gives `gh` real stdin to read.

**Diagnosing it after the fact:** print the length in the job, next to where the
token is used. The length is not the secret and CI cannot mask it, and `0` versus
`93` distinguishes an empty secret from a bad one in a single line — nothing else
does.

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
