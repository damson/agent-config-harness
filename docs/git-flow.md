# Git Flow

Two long-lived branches, gitflow-style:

| Branch | Role |
|---|---|
| `develop` | Integration. Feature branches are cut from it and land back into it. Config work is tested here. |
| `main` | Releases. Only ever updated by promoting `develop`. |

Neither takes a direct push; every change lands via PR.

---

## Branch Naming

```
ai-config/<type>-<domain>-<YYYY-MM-DD>
```

| `<type>` | When to use |
|---|---|
| `sync` | Pulling improvements from an active project back into the repo (`just sync`) |
| `improve` | After `claude-md-improver` proposes edits and you accept them |
| `fix` | Resolving a contradiction or repairing a broken link |
| `new-domain` | Adding a new workspace domain |

Examples:
- `ai-config/sync-mobile-2026-05-25`
- `ai-config/improve-web-react-2026-05-26`
- `ai-config/new-domain-data-extraction-2026-05-24`

Suffix with `-2`, `-3`, etc. if the branch name already exists.

---

## Protection on `main` and `develop`

`just setup` installs a pre-push hook in this repo that refuses direct pushes to `main` and `develop`. Find it with `git rev-parse --git-path hooks`; usually `.git/hooks/pre-push`, but from a worktree the hooks live in the common dir, so the path is not `.git/hooks` there. One hook covers the repo and every worktree of it. Re-run `just setup` after changing it in `bin/setup.sh`, since the installed copy does not update itself. To override it (rare; not recommended):

```bash
git push --no-verify
```

CI also runs on every PR and on pushes to both protected branches. Tests, shellcheck, and secret lint must pass.

---

## When `gh` returns HTTP 503

GitHub degrades GraphQL and REST independently, and `gh pr create`, `gh pr close` and
`gh pr merge` all go through GraphQL. During a partial outage they fail while the REST
endpoints keep working, so reach for those rather than waiting:

```bash
gh api -X POST /repos/<owner>/<repo>/pulls \
  -f title="…" -f head="<branch>" -f base="develop" -F body=@body.md
gh api -X POST /repos/<owner>/<repo>/issues/<n>/comments -f body="…"
gh api -X PATCH /repos/<owner>/<repo>/pulls/<n> -f state=closed
```

Retry loops must test the command's own status, not a pipeline's: `if out=$(gh …);`
rather than `gh … | tail -1`, which reports `tail` and "succeeds" on every 503.

---

## Releasing

`main` only ever moves by promoting `develop`, via a PR like any other change.
Nothing is authored on a release branch; if a fix is needed mid-release, it
lands on `develop` first and the release PR picks it up.

**A standing release PR is kept open for you.** `.github/workflows/release-pr.yml`
runs `bin/open-release-pr.sh` every Monday (and on demand via *Run workflow*),
opening the PR if none is open and refreshing its inventory if one is. It never
merges; promotion stays a human decision. Locally:

```bash
just release           # open or refresh it
just release-preview   # print the body, touch nothing
```

The script fills in what can be derived: commit count, the PRs in the batch,
the diffstat, the oldest unreleased commit. Two sections it deliberately leaves
blank, because they need judgement:

- **the plain-words summary**, and
- **a before/after diagram, which a release must carry.** Individual PRs skip
  the diagram when nothing moves; across a batch something almost always has,
  and the release is the only place a reader sees where the repo ended up
  rather than one step of the journey.

### Why cadence matters here

Letting `develop` run ahead has a specific cost beyond a large review: GitHub
only honours `closes #N` on a merge into the **default** branch. Every closing
keyword written on a PR into `develop` does nothing until the next promotion, so
a long gap leaves fixed issues sitting open; five of them, at the last count.

### After the release: bring `main` back

Promotion is one-directional, so the merge commit it creates on `main` never
reaches `develop`. The trees stay byte-identical, which is exactly why this goes
unnoticed: nothing in a working copy looks wrong, and only a commit count
reveals it:

```bash
git diff origin/develop origin/main          # empty
git rev-list --count origin/develop..origin/main   # 5
```

That was the real state after five releases: `develop` reported as five commits
behind a branch it was missing nothing from.

`.github/workflows/backmerge-pr.yml` now opens the PR on every push to `main`,
running `bin/open-backmerge-pr.sh`. By hand:

```bash
just backmerge           # open or refresh it
just backmerge-preview   # print the body, touch nothing
```

Like the release PR it **never merges**; merging into a protected branch stays
a human decision. The body distinguishes the two cases, because they deserve
different attention:

- **History only:** trees identical, no file can change. A formality.
- **Carries file changes:** something landed on `main` without going through
  `develop`, i.e. a hotfix. Review it as a normal change. Note that a PR opened
  by `GITHUB_TOKEN` does not trigger CI, so this case wants a manual run or a PAT.

---

## Two things that make a PR-opening workflow fail

Both bit the automation here, and neither is visible from the workflow file.

**A job-level `permissions: pull-requests: write` is not sufficient.** The
repository must also allow it:

```
Settings → Actions → General → Workflow permissions
  ☑ Allow GitHub Actions to create and approve pull requests
```

```bash
gh api -X PUT repos/<owner>/<repo>/actions/permissions/workflow \
  -F can_approve_pull_request_reviews=true \
  -f default_workflow_permissions=read
```

Without it, `gh pr create` inside a workflow fails with *GitHub Actions is not
permitted to create or approve pull requests*, a message that reads like a token
problem and is not one.

**A workflow with no `pull_request` trigger is never exercised by review.** The
release and back-merge workflows run only on `push` to `main`, so a PR that moves
or renames a script they call goes green and fails on the next release instead.
When relocating a script, grep **every** workflow, not just the one CI runs:

```bash
grep -rn 'run: \./' .github/workflows/
```

---

---

## The `just sync` Flow

```
just sync ~/workspace/mobile/acme-mobile
```

What it does:
1. Auto-detects the domain via `detect-domain.sh` ("mobile" in this case).
2. Diffs each managed file (`AGENTS.md`, `CLAUDE.md`, `.cursorrules` for mobile) against the project's local copy.
3. If anything differs, copies the project's version into `workspace/mobile/`.
4. Creates branch `ai-config/sync-mobile-<YYYY-MM-DD>` (or appends `-2`, `-3` if it already exists).
5. Commits with message `sync: mobile config from acme-mobile`.
6. Pushes the branch to `origin`.
7. Opens a PR against `develop`:
   - `gh` if installed (GitHub)
   - `glab` if installed (GitLab)
   - Otherwise prints branch info for manual PR creation.
8. Re-scores the synced domain and posts the **full benchmark table** as a PR/MR comment, so reviewers see how this change moved scores across every domain. Set `AI_SETUP_SKIP_EVAL=1` to skip (CI, no Claude CLI).
9. Returns you to the original branch.

If nothing differs, the command exits early with `Nothing to sync`.

---

## Merging

Land a PR with `gh pr merge --merge` when its commits are each one logical
change; squashing collapses exactly the history the one-change-per-commit rule
exists to produce. Squash only where the branch is a single change plus fixups.

## PR Conventions

- **Title:** `ai-config: <type> <domain> - <short summary>`
  - e.g. `ai-config: sync mobile - pickup new ktlint rule`
- **Body:** what changed and why. Mention the source project. Include score deltas if you ran `just eval` before and after.
- **Reviewers:** none required for personal repo, but CI must pass.

---

## Stealth Workflow

For host repos where you want to use centralised configs without dirtying the host repo's git history.

### Apply stealth

```bash
just stealth ~/workspace/mobile/acme-mobile AGENTS.md
```

This replaces `acme-mobile/AGENTS.md` with a symlink into `workspace/mobile/AGENTS.md` and marks the file `skip-worktree` so git in the host repo ignores the swap.

### Working with stealth

Inside the host repo:

```bash
git spull          # pull with stealth handling (auto-syncs any teammate updates back into this repo)
git scommit -m …   # commit AI rule edits: creates a branch in the host repo and opens an MR
```

Both aliases are installed by `just setup`.

### Restore (before tricky merge/rebase)

```bash
just unstealth ~/workspace/mobile/acme-mobile AGENTS.md
```

Clears `skip-worktree` and restores the file from the host repo's git index. Re-apply with `just stealth` afterwards.

### Materialize (one-shot stage)

```bash
just materialize ~/workspace/mobile/acme-mobile AGENTS.md
```

Stages this repo's current content as a normal file in the host repo (so you can commit it there) and immediately restores the stealth symlink. Use when you specifically want to land the rule in the host repo.
