# Shell gotchas

Shell behaviour that produces a **wrong result rather than an error**. Anything
that fails loudly does not belong here; a stack trace teaches itself.

The login shell on these machines is `zsh`, and every entry below is a zsh
behaviour that `bash` does not share. A command copied from a bash-flavoured
README can therefore work everywhere it was written and fail here.

## `.` searches `$PATH`, so `. .env` does not read `./.env`

```bash
set -a && . .env && set +a       # ✗ zsh: no such file or directory: .env
set -a && . ./.env && set +a     # ✓
```

zsh's `source`/`.` builtin looks a bare filename up in `$PATH`, not in the
current directory. The file is right there, `ls` shows it, and the error still
says it does not exist, which reads as a missing file rather than a lookup
rule, so the usual reaction is to go hunting for the file.

Give it a path with a slash in it. `. ./.env`, or an absolute path.

## A `:` after a variable is a history modifier

```bash
git cat-file -p "$branch:path/to/file" > out.txt     # ✗ writes an empty file
git cat-file -p "${branch}:path/to/file" > out.txt   # ✓
```

zsh applies history-expansion modifiers to `$var:x`: `:r` strips the
extension, `:h` the last path component, `:t` the directory. So
`"$b:reports/x.md"` parses as "`$b` with `:r` applied" followed by the literal
`eports/x.md`, and the command receives a mangled argument.

**This one is dangerous because the failure is empty output.** A loop that
backs up files this way reports the right number of files created, each of them
zero bytes. Verified against real damage: eleven source-health reports were
"preserved" as empty files immediately before their branches were deleted; only
checking the byte counts caught it.

Brace the variable whenever a `:` follows it. If a loop writes files, check
sizes rather than counts: `wc -c` over the output, not `ls | wc -l`.

## An unquoted variable is one word, so a list in a string never splits

```bash
files="a.md b.md"
for f in $files;    do …; done   # ✗ zsh: one iteration, f="a.md b.md"
for f in ${=files}; do …; done   # ✓ three words
files=(a.md b.md);  for f in $files; do …; done   # ✓ better: an array
```

`bash` word-splits an unquoted expansion; zsh does not. Code copied from a
bash-flavoured script therefore runs, exits 0, and silently does a fraction of
the work: the loop body executes once with the whole string as its argument.

**The damage is a false negative from a checking command.** `git diff --quiet
"$a" "$b" -- $files` passes the list as a *single* pathspec, which matches no
file, so the diff is empty and the check reports "no difference" for files it
never compared. Verified against real damage: this reported two branches as
fully merged, on the strength of comparisons that never ran, moments before
those branches were to be deleted. Both were in fact identical to develop,
established afterwards by a check that actually looked.

Use an array when you build a list. Reach for `${=var}` only when the string
arrives already-joined from elsewhere. The tell in the output is a loop that
prints one line where it should print several, or several names on a line that
should hold one.

## A failing `[[ ]]` mid-test does not fail a bats test

```bash
@test "example" {
  [[ "$output" == *"expected"* ]]   # ✗ inert unless it is the LAST command
  assert_contains "$output" "expected"   # ✓ a real command; errexit catches it
}
```

Proved side by side, bats 1.14:

| Test body | Result |
|---|---|
| `[[ "hello" == "goodbye" ]]` then `echo done` | **passes** |
| `false` then `echo done` | fails |
| `[[ "hello" == "goodbye" ]]` as the last line | fails |

So the same assertion is live or inert depending on what follows it. `[ ... ]`
and any ordinary command behave correctly; only the `[[ ]]` compound is skipped
by errexit in that position.

This is why `tests/helpers/common.bash` provides `assert_contains`,
`assert_not_contains`, `assert_starts_with` and `assert_not_starts_with`: they
end in a `grep` or a `return 1`, which bats does catch wherever they appear.

**28 of the 58 assertions in this suite were inert** when this was found. All 28
turned out to be true once made live, but the suite could not have told anyone
otherwise. Found by deleting a section the test claimed to require and watching
the test pass.
---

## Appendix: `status` is read-only

This one fails loudly, so by the rule at the top it does not belong above. It is
kept because it is the same zsh-versus-bash portability trap as the rest: the
snippet runs everywhere it was written and dies here.

```bash
out=$(some-command); status=$?      # ✗ zsh: read-only variable: status
out=$(some-command); rc=$?          # ✓
```

zsh reserves `status` as an alias for `$?`, so assigning to it is an error rather
than a shadowing. `bash` has no such reservation, which is why a captured
`status=` reads as perfectly ordinary until it runs here.

## Appendix: the `find` in an agent session is not the system `find`

Also loud rather than silent, but it makes a *verification* silently wrong,
which is worse than either.

Claude Code's shell snapshot defines `find` as a **function** that runs `bfs`
(GNU-flavoured) instead of `/usr/bin/find` (BSD). So a predicate checked inside a
session can behave differently from the same predicate in the user's terminal:

```bash
$ type find
find is a shell function from ~/.claude/shell-snapshots/snapshot-zsh-*.sh

$ find "$dir" -newermt @1000000000       # the function → bfs
…two results, exit 0

$ /usr/bin/find "$dir" -newermt @1000000000
find: Can't parse date/time: @1000000000
```

This produced a wrong conclusion for real. A skill was corrected to say BSD
`find` rejects `-newermt @<epoch>`; checking that claim in-session appeared to
*disprove* it, because the check ran under `bfs`. The correction was right and
the verification was wrong.

**When a skill or doc makes a claim about a system tool, verify with the absolute
path** (`/usr/bin/find`, `/bin/sh`), not the bare name. `type <cmd>` says which
you are about to get. The same applies to any command the harness wraps.

For the record, on macOS 26.5 BSD `find`: `-newermt '-5 minutes'` **works**,
`-newermt @<epoch>` is **rejected**, and `-mmin -5` works on both. An earlier
note in this repo claimed the relative form was the GNU-only one, the opposite
of what running it shows.
