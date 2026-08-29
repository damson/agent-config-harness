---
name: rewrite-pr-history
description: >
  Use when the user asks to fix PR conflicts, drop or reorder commits on a
  feature branch, rebase a branch onto a freshly-merged main, or otherwise
  rewrite history on an open PR. Bundles the safe rebase → verify →
  force-push-with-lease → PR-state-check cycle, including SSH-agent recovery
  and per-branch authorization gates.
---

# Rewrite PR history

When the user says "fix conflicts on PR N", "remove the X commit from PR N",
"rebase PR N onto main", "reorder commits on PR N", "drop the last commit",
or similar, run the procedure below.

The goal: never lose the user's work, never force-push to a shared branch,
never skip pre-flight checks. Every step is recoverable if interrupted.

## Procedure

### 1. Read PR state

```bash
gh pr view <N> --json baseRefName,headRefName,mergeable,mergeStateStatus,reviewDecision,commits
```

Confirm:
- Head branch is **not** `main`, `master`, `develop`, or any protected branch.
- Head branch matches a user-owned naming pattern (e.g. `ai-config/*`,
  `<user>/*`). If it looks shared, ask before rewriting.
- If `reviewDecision` shows pending or approved reviews, surface that — review
  comments may go stale after a rewrite. Ask before continuing.

### 2. Sync working tree

```bash
git fetch origin --prune
git checkout <head-branch>
```

Verify clean working tree (`git status -s` returns empty). If dirty, stop and
ask the user — never auto-stash without consent.

### 3. Show the plan

Run `git log --oneline origin/<base>..HEAD` and `git diff origin/<base> --stat`.
State the intended action in plain words (e.g. "I'll drop commit X by rebasing
--onto origin/main starting after it"). **Wait for explicit user "go"** before
rewriting.

### 4. Rewrite

Use the smallest-blast-radius command for the job:

| Goal | Command |
|---|---|
| Resolve conflicts with new main | `git rebase origin/main` |
| Drop one commit in the middle | `git rebase --onto <base> <commit-to-drop> <branch>` |
| Reorder / squash | `git rebase -i origin/<base>` only if the host supports interactive input — Claude Code in autonomous mode does NOT; in that case combine `git rebase --onto` + `git cherry-pick` to achieve the same result without `-i` |
| Reword last commit only | `git commit --amend` (verify HEAD is the right commit first) |
| Split last commit | `git reset --soft HEAD~` then re-stage in parts |

Non-interactive drop/reorder: `git rebase -i` requires terminal input — pipe
edits through `GIT_SEQUENCE_EDITOR=<script> git rebase -i <base>` (the script
does e.g. `sed -i '' 's/^pick <sha>/drop <sha>/' "$1"`).

Re-verify with `git log --oneline origin/<base>..HEAD` and
`git diff origin/<base> --stat` after every step. Also check `git diff HEAD` — a
commit adding a line already on the base branch (different context) creates a
duplicate in the blob; the IDE removes it silently from disk.

### 5. Local checks before pushing

Run the project's documented test command. Detect it in this order:
1. `just --list` — use a recipe named `test`, `check`, or `verify` if present.
2. `package.json` — use the `scripts.test` value.
3. `Makefile` — use a `test` target if present.
4. Fall back to known project conventions: `bats tests/` for shell repos,
   `pytest` for Python, `cargo test` for Rust.

Also run the linter the repo CI uses (check `.github/workflows/` for hints —
`shellcheck`, `eslint`, `ruff`, etc.).

Don't push if checks fail — fix locally first.

### 6. SSH-agent pre-flight

```bash
ssh-add -l
```

If the agent has no identities, add the key the host uses (check `~/.ssh/config`
first; fall back to `~/.ssh/id_rsa` or `~/.ssh/id_ed25519`):

```bash
ssh-add ~/.ssh/<keyfile>
ssh -T git@github.com   # or git@gitlab.com
```

Confirm the auth message names the expected user before pushing.

### 7. Force-push with lease

```bash
git push --force-with-lease origin <branch>
```

**Never** use plain `--force`. `--force-with-lease` refuses to clobber if the
remote moved since the last fetch — if it rejects, stop and surface the diff
between expected and actual remote state.

### 8. Verify on the platform

```bash
gh pr view <N> --json mergeable,mergeStateStatus,commits -q \
  '{state:.mergeStateStatus,mergeable:.mergeable,commits:[.commits[].messageHeadline]}'
```

Confirm:
- `mergeable: MERGEABLE`
- `mergeStateStatus: CLEAN` (or `UNSTABLE` if CI is still running — that is OK)
- Commit list matches the planned outcome.

Report state back to the user.

## When to STOP

- **Branch is `main` or shared** → refuse. Suggest a revert PR or a forward-fix.
- **`--force-with-lease` is rejected** by remote → stop. Surface the diff,
  ask the user how to proceed. Do not switch to plain `--force`.
- **No explicit per-branch authorization for force-push** → ask. Prior
  authorization on one branch does not extend to another.
- **PR has approved reviews or unresolved comments** → ask before rewriting;
  reviewers may need to re-approve, and review comments anchor to commits.
- **CI was green and the rewrite is purely cosmetic** → ask if rewrite is worth
  the cache invalidation; sometimes a follow-up commit is better.
- **Working tree is dirty** → ask the user. Never silently stash.
