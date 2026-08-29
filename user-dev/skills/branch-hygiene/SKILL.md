---
name: branch-hygiene
description: >
  Use when a PR has just merged on `origin/develop` or `origin/main`, when multiple open
  PRs share an ancestor that has now landed, when the user says "rebase the open PRs" /
  "manage open PRs" / "PR X merged, clean up" / "fix conflicts" / "deal with conflicting
  PRs", or after running `gh pr merge`. Goal — drop duplicate commits introduced by the
  merge, force-push the open PRs onto the new base, prune dead worktrees and branches,
  and close the issues the merged PR's keywords could not.
---

# Post-merge branch hygiene

After any merge to `develop` / `main`, the other open PRs that branched from the merged work appear `CONFLICTING` on GitHub because the merge commit assigned new SHAs to commits whose patches are now in the base. Resolution is mechanical: rebase + force-push.

## Procedure

1. **Sync remote state**:
   ```bash
   git fetch origin --prune
   ```

2. **List open PRs**:
   ```bash
   gh pr list --state open --json number,headRefName,baseRefName,mergeable,mergeStateStatus
   ```

3. **For each open PR where** `mergeable=CONFLICTING` **or** `mergeStateStatus` is
   `DIRTY` / `BEHIND`. Not `BLOCKED` or `UNSTABLE` — those mean a red check or a
   missing review, which a rebase does not fix and a force-push only reruns:

   a. Pick the worktree to work in — call it `$wt`:
   ```bash
   git worktree list                  # find any path already on <branch>
   git -C <path> status --porcelain   # empty → reuse it as $wt
   ```
   No worktree holds the branch → add a temp one, which step 4 removes again:
   ```bash
   git worktree add /tmp/rebase-pr-<n> <branch>
   ```
   A worktree holds it but is **dirty** → skip this PR and say so; `git worktree
   add` refuses a branch already checked out, and forcing it races two worktrees
   over a branch you are about to force-push.

   Every command in the rest of step 3 runs against `$wt`.

   b. Rebase onto the PR's new base:
   ```bash
   git -C "$wt" rebase origin/<base-branch>
   ```
   Git auto-skips commits whose patches are already on the base (the duplicate ones). Watch the `warning: skipped previously applied commit <sha>` lines — those confirm the cleanup.

   c. **Inspect the result**:
   ```bash
   git -C "$wt" log --oneline origin/<base-branch>..HEAD
   ```
   Every commit here should be this PR's own work. An unexplainable one (a
   cherry-pick from another worktree, a stray amend) is a STOP — see below.

   d. Run the project's own test command in `$wt` — confirm green. Detect it, never assume a
   toolchain: a `test` / `check` / `verify` recipe in `just --list`, else
   `scripts.test` in `package.json`, else a `test` target in the `Makefile`, else the
   language default (`bats tests/`, `pytest`, `cargo test`, `go test ./...`). If none
   of these resolves, ask rather than guess — a skipped test suite reads exactly like
   a green one.

   e. Force-push with lease (refuses to clobber if upstream moved):
   ```bash
   git -C "$wt" push --force-with-lease
   ```

4. **Worktree cleanup**:
   ```bash
   git worktree list
   ```
   Remove a worktree with no uncommitted changes (`git -C <path> status
   --porcelain` empty) when **either** its branch no longer exists on origin (it
   was deleted post-merge), **or** it is one of the `/tmp/rebase-pr-*` temporaries
   step 3a added — those outlive their branch and step 4 is the only thing that
   collects them:
   ```bash
   git worktree remove <path>          # refuses on untracked files; inspect,
                                       # then --force once you know what they are
   ```

   Then prune the branch itself. A merged PR leaves both copies behind. Delete a
   listed branch only when it has no open PR and no surviving worktree:
   ```bash
   def=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD | cut -d/ -f2-)
   git branch --merged origin/<base-branch> | sed 's/^[*+ ] //' |
     grep -vxE "<base-branch>|$def"      # never the base or the default branch
   gh pr list --state open --json headRefName -q '.[].headRefName'   # keep these
   git branch -d <branch>                 # refuses if unmerged — trust it
   git push origin --delete <branch>      # skip if the merge already deleted it
   ```

5. **Close the issues the merge did not** — this one is about the PR that just
   merged, not the rebased ones. GitHub honours `Closes #N` only when
   the PR's base is the repo's **default** branch, so in a gitflow repo every
   closing keyword on a `develop`-based PR does nothing:

   ```bash
   gh pr view <n> --json closingIssuesReferences -q '.closingIssuesReferences[].number'
   ```

   Empty output means nothing was closed. Read the intent off the body instead —
   that is where the keywords were written:

   ```bash
   gh pr view <n> --json body -q .body |
     grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #[0-9]+' |
     grep -oE '[0-9]+' | sort -u
   ```

   (A body naming the same issue twice would otherwise be closed twice.)

   Close each by hand, citing the merge commit so the trail survives:

   ```bash
   gh issue close <n> --comment "Fixed in #<pr>, merged to <branch> as <sha>."
   ```

   Skip this where the PR's base *is* the default branch — there the keywords
   fired and a manual close would be noise.

6. **Re-snapshot PR statuses** — re-run step 2's `gh pr list`. GitHub computes
   `mergeable` asynchronously, so a query fired straight after the push answers
   `UNKNOWN`; wait and re-query rather than reporting that. Then report:

   ```
   PR #3: rebased onto develop, dropped 5 duplicate commits, CLEAN
   PR #4: rebased onto develop, dropped 2 duplicate commits, CLEAN
   PR #5: was already CLEAN, no action
   ```

## When to STOP and ask

- The rebase empties the branch — every commit was a duplicate, so step 3c's log
  prints nothing. Do not force-push a zero-diff PR and call it CLEAN: the work is
  already on the base, so close the PR instead.
- A real conflict (not a duplicate-patch artefact) appears during rebase → don't auto-resolve; abort with `git rebase --abort` and ask the user.
- A rebase produces a commit on top that you can't explain (e.g. a cherry-pick from another local worktree) — surface it before pushing.
- Tests fail post-rebase → don't push; report the failure with the file:line.
- `--force-with-lease` is rejected → the remote moved, and fetching alone does
  not change that: your branch still lacks the new upstream commits, so a bare
  retry fails identically. Fetch, rebase onto the moved base, retry once. Still
  rejected means someone else is pushing that branch — stop and ask.

## Safety rules

- Never operate on `main` or `develop` directly — only on feature branches.
