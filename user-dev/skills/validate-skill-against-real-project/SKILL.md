---
name: validate-skill-against-real-project
description: >
  Use when a portable or generic skill has never been executed against a real
  project, before trusting it or calling it done. Fire on "validate the skill",
  "does this skill actually work", "test it against a real repo", when a skill
  claims to work on "any <stack> project" and no run is on record, or when a skill
  was reviewed by reading it rather than running it. Skip for project-specific
  skills, which are allowed to assume one build's wiring.
---

# Validate a skill against a real project

A skill reads as correct long after it stopped being correct. Task names invert,
a tool's flag turns out to be a GNU extension, a `grep` returns nothing on a
layout the author never had. None of it is visible by reading — the sentences stay
plausible. Running the skill's own commands is the only check that separates a
procedure that works from one that merely sounds like it does.

## Procedure

### 1. Pick a target that matches the claimed scope

Read the skill's `description` for the scope it claims, then choose a project
inside it. Record what makes this target specific: stack and versions, module
count, OS, shell, and whether the project has ever been built.

```bash
ls -d */ | head; git -C . rev-parse --show-toplevel     # candidates and root
uname -sr; echo "$SHELL"                                # OS and shell
```

Where several projects qualify, **pick the smallest** — fewest modules, plainest
layout. A skill claiming "any project of kind X" claims the whole range, and the
small end is where generic skills break, because the author's own project was not
there. Say which end you tested; one target cannot prove the range.

### 2. Extract every executable claim

Go through the skill and list what can be run or checked:

- commands, and every flag in them
- task, file and directory names it predicts
- assertions about a tool's behaviour ("X rejects Y", "this is a GNU extension")
- anything phrased as a table of expected names

Prose about judgement is out of scope here. Anything with a shell in it is in.

### 3. Run each one verbatim

Do not adapt the command to make it work — an adapted command validates your
adaptation, not the skill.

```bash
out=$(<command from the skill> 2>&1); rc=$?
echo "rc=$rc"; echo "$out" | head
```

Capture the exit code **before** piping. A pipeline reports its last command, so
`cmd | head` returns `head`'s status and a failing `cmd` reads as success.

### 4. Check tool claims against the system binary

Before believing any "this tool rejects that" claim, find out which binary you
have:

```bash
command -v <tool>; <tool> --version 2>&1 | head -1
```

A friendlier drop-in on `$PATH` — installed years ago and forgotten — accepts
syntax the stock tool refuses, and makes a broken command look fine. If
`command -v` returns anything other than the system path, re-run the claim against
that path directly and compare **exit codes first**, then stderr: a non-zero exit,
or a parse/usage error on one and not the other, is a disagreement. Differing
output for the same exit code is usually the projects differing, not the tools.

Where the system has no such binary at all (common for tools installed only via a
package manager), there is no stock behaviour to appeal to — record the version you
tested and mark the claim as verified for that build only.

### 5. Exercise the degenerate cases

Generic skills are written against the author's project, which is rarely the
simple one. Run the skill's discovery steps against:

- the smallest layout the scope allows (single module, one package)
- a tree that has never been built, so the output directories do not exist
- an empty result set — no baselines, no matches, nothing configured

You rarely have such a project to hand, so make one — these are cheap:

```bash
d=$(mktemp -d); (cd "$d" && git init -q)        # empty tree, nothing built
git clone --depth 1 <repo> "$d/fresh"           # real project, never built
```

Run the skill's *discovery* steps there (its greps, its `find`s, its "locate the
module" commands). They are read-only, so this costs nothing but the clone.

A step that has no branch for these is a defect even when its happy path works.
Note especially any instruction that rules out the answer the command returns.

### 6. Separate what you can judge from what you cannot

Two different things get called "does the skill work":

| Question | Judgeable here |
|---|---|
| Do its commands run and its claims hold? | Yes — that is steps 3–5 |
| Does it fire unprompted, and follow its own steps? | **No, not by you** |

Once you have read a skill's procedure and its test plan, you cannot score whether
it would have fired on its own, or whether an agent following it would take the
right step — you already know the answers. Say so and leave that half to a session
without this context. Reporting it anyway is the most common way this work goes
wrong.

### 7. Report per skill, with evidence

One issue per skill, in the repo that owns it:

```bash
gh issue create --repo <owner>/<repo> --title "skill: <name> — <what breaks>" \
  --body-file <file>
```

Title it `skill: <name> — <what breaks>` so several reports stay sortable. For each
defect give, in order: the quoted line from the skill, the command you ran, its exit
code and output, then what it costs someone following it.
Close with what was **not** covered — steps needing credentials or integrations
you lacked, and the behavioural half from step 6.

Quote a suggested fix where you have one, and mark any claim you inferred rather
than observed as unverified. A confident wrong fix in an issue outlives the issue.

## When to STOP

- **No available project matches the claimed scope.** Say so rather than
  validating against a mismatched stack — a defect found outside the scope is not
  a defect.
- **A step needs an integration the environment lacks** (a credential, a design
  tool, a paid API). Validate the offline steps, report the rest as not covered.
  Never let "could not run it" become "it passed".
- **A fix is obvious and small.** Filing and fixing are separate acts — the report
  is the deliverable here. Fix in its own change, against the report.
