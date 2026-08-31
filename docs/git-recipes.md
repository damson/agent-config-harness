# Git recipes

Syntax worth looking up rather than memorising. The *policy* — one logical change
per commit, a worktree per feature, never push to a protected branch — lives in
`docs/git-flow.md` and the config files this repo manages. This file is only the how.

## Worktrees with `git gtr`

Pass the **branch name**, never the path — `gtr` derives the directory itself.

| Goal | Command |
|---|---|
| New worktree off the default parent | `git gtr new <branch>` |
| Stacked on another branch | `git gtr new <branch> --from <ref>` |
| Where did it put it? | `git gtr go <branch>` (prints the path) |
| Remove it | `git gtr rm <branch> --force --yes` |

`--force` is what lets it remove a worktree holding submodules; `--yes` skips the
confirmation prompt. Neither overrides uncommitted work being lost — check
`git -C <path> status --porcelain` first if the worktree was ever edited.

`gtr` is not installed everywhere. Where it is missing, fall back to:

```bash
git worktree add -b <branch> <path> origin/<parent>
```

and **say that you fell back**, rather than substituting silently — the two do not
produce the same layout, and a later `git gtr rm` will not find the result.

### Before merging with `--delete-branch`

`gh pr merge --delete-branch` has to leave the branch it is deleting, and it falls
back to `main` — which the primary checkout usually holds, so it fails with
`'main' is already used by worktree`. Check out `develop` in the worktree first.

## Amend a commit that is not HEAD

```bash
git commit --fixup=amend:<hash>          # message file must START with: amend! <original subject>
GIT_SEQUENCE_EDITOR=: git rebase --autosquash --autostash <hash>~1
```

Use plain `--fixup <hash>` when you are only adding changes and keeping the message.

**The `amend!` first line is load-bearing.** Autosquash matches on it; overwrite it —
by passing a `GIT_EDITOR` that replaces the whole message, say — and the rebase
still prints *Successfully rebased and updated*, having silently left your fixup as
an ordinary extra commit. Check `git log --oneline` for the commit count you
expected, not for the success line.

## Reword a commit that is not HEAD

```bash
GIT_SEQUENCE_EDITOR="sed -i '' 's/^pick <hash>/reword <hash>/'" \
  GIT_EDITOR="cp <msgfile>" git rebase -i <hash>~1
```

Non-interactive despite the `-i`: the sequence editor rewrites the todo list and
`GIT_EDITOR` supplies the new message from a file. `sed -i ''` is the BSD/macOS
form — GNU `sed` takes `-i` with no argument.

## Rebase a stacked branch after its parent is squash-merged

Two things go wrong, in order, and the second reads like the first's fault.

**GitHub retargets a child PR only when the base branch is deleted.** Merging
the parent is not enough — and `gh pr merge --delete-branch` refuses while a
worktree holds the branch, which is exactly when you are stacking. Until it is
retargeted the child points at a branch nobody will push to again, and its
checks run against that stale base:

```bash
gh pr edit <child> --base develop
```

**Then the rebase conflicts, because a squash is not the commits it squashed.**
`git rebase origin/develop` tries to replay the parent's commits; `develop`
holds them only as one commit with a different hash, so every file the parent
touched conflicts with itself. Replay just your own instead:

```bash
git log --oneline origin/<parent>..HEAD              # what is actually yours
git rebase --onto origin/develop origin/<parent> <child-branch>
git diff --stat origin/develop...HEAD                # the check
```

The last line is the whole verification: it must list only the files your
branch touched. If the parent's files appear, the rebase swept in commits that
were already merged.

If the parent branch is already deleted, use the SHA it pointed at — the child's
reflog has it (`git reflog show <child-branch>`), as does the merged PR.
