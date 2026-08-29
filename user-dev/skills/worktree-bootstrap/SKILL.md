---
name: worktree-bootstrap
description: >
  Use immediately after `git worktree add` or `git gtr new` creates a fresh
  worktree for any repo (a web/Next app, a Node/TypeScript backend, a Python
  data/ETL project, an Android/Gradle app, or anything else) and it won't run
  or build because .gitignored env files and installed
  dependencies weren't carried over. Fire when the user says "set up the
  worktree", "the new worktree won't build/run", "missing .env in the worktree",
  "node_modules is missing", "gradle can't find the SDK / local.properties", or
  a dev server errors on missing env vars right after a worktree is created.
  Skip when the repo ships its own bootstrap skill — that one knows its extra
  credential files and hooks. Skip if the worktree has already run once.
---

# Bootstrap a fresh worktree (generic)

A new worktree shares the repo's git history but is a **separate working tree** on disk. Two classes of thing do NOT come across, and both cause confusing first-run failures:

1. **.gitignored config** — `.env`, `.env.local`, service credentials, local settings. The app boots, then errors on a missing variable that "works on the other branch".
2. **Installed dependencies and generated artifacts** — `node_modules/`, a Python `.venv/`, Prisma/codegen output. These are gitignored or per-tree, so a fresh worktree has none.

This skill copies the first from a donor worktree and rebuilds the second for the detected stack, so the next `dev`/`build`/`test` works on the first try. It covers what any repo needs; where a repo ships its own bootstrap skill, defer to that instead — it will know the extra credential files, submodules and hooks this one deliberately omits.

## Procedure

### 1. Detect the stack

From the worktree root:

```bash
ls package.json pnpm-lock.yaml yarn.lock package-lock.json \
   pyproject.toml poetry.lock requirements.txt go.mod \
   settings.gradle settings.gradle.kts build.gradle gradlew 2>/dev/null
```

| Signal | Stack | Dep install | Common gitignored config |
|---|---|---|---|
| `pnpm-lock.yaml` | Node (pnpm) | `pnpm install` | `.env`, `.env.local`, `.env.*.local` |
| `package-lock.json` | Node (npm) | `npm ci` | `.env`, `.env.local` |
| `yarn.lock` | Node (yarn) | `yarn install --immutable` | `.env`, `.env.local` |
| `poetry.lock` | Python (poetry) | `poetry install` | `.env` |
| `requirements.txt` / `pyproject.toml` | Python (venv) | `python -m venv .venv && .venv/bin/pip install -e .` | `.env` |
| `go.mod` | Go | `go mod download` | `.env`, local config |
| `settings.gradle{,.kts}` / `gradlew` | Gradle / Android | none separate — Gradle resolves on first build | `local.properties`, `keystore.properties`, `*.jks` |

If nothing matches, treat it as **general**: copy whatever `.gitignored` config the donor has (step 3) and skip the dep install.

### 2. Find a donor worktree

Any existing worktree of the same repo has the machine-local config (it's per-machine, not per-branch):

```bash
SOURCE=$(git worktree list --porcelain \
  | awk '/^worktree / {print $2}' \
  | grep -v "^$(pwd)$" \
  | head -1)
echo "Donor: ${SOURCE:-<none — this is the only worktree>}"
```

If `SOURCE` is empty, ask the user where their primary checkout lives — don't fabricate config.

### 3. Copy the .gitignored config

Copy only the files git ignores (never tracked files). List what the donor actually has, then copy the env/config among them:

```bash
# --ignored is REQUIRED: the files to carry over are gitignored, so plain
# --exclude-standard (which HIDES ignored files) returns nothing.
git -C "$SOURCE" ls-files --others --ignored --exclude-standard \
  | grep -E '(^|/)\.env($|\.)|\.env\.local|local\.settings|\.envrc|local\.properties|keystore\.properties|\.jks$' || true
```

Copy each match into the same relative path here (create parent dirs as needed). Then confirm the files this stack needs are present — `.env` / `.env.local` for a Node/Python app, `local.properties` (plus `keystore.properties` if the app signs) for Android. If an expected file is missing, the donor didn't have it either — stop and ask, don't fabricate it.

### 4. Install dependencies (and submodules)

Run the command from the step-1 table for the detected stack. For Node, match the lockfile's package manager exactly — using `npm install` where the repo uses `pnpm` rewrites the lockfile and is a real bug. Gradle and general repos have no separate install step (Gradle resolves on the first build).

If the repo has submodules, a fresh worktree does not populate them:

```bash
[ -f .gitmodules ] && git submodule update --init --recursive
```

### 5. Run codegen / prerequisites (only if the repo has them)

Check `package.json` scripts (or the Makefile / `pyproject.toml`) for a `postinstall`, `generate`, `prepare`, `codegen`, or `prisma generate` step and run it. Skip if none — don't invent one.

### 6. Verify the worktree actually works

Run the cheapest command that exercises real config + deps, not just a lockfile check:

- Node app: `pnpm typecheck` (or `pnpm build`), then start the dev server briefly if the change is runtime-facing.
- Python: `pytest -q` or `python -m <package> --help`.
- Android/Gradle: `./gradlew help -q` — the cheapest full configure; it proves `local.properties` resolves — then the module's build/test task.
- General: the repo's documented smoke command.

A green install is not proof — the app booting and reading its env is. If it fails on a missing variable, step 3 missed a file; re-list the donor's ignored files.

## When to STOP and ask

- **No donor worktree and no known primary checkout.** The bootstrap needs a source for machine-local config; don't fabricate `.env` values or invent secrets.
- **The donor's `.env` contains real secrets and the worktree is destined for a shared/remote location.** Copying secrets into a shell others can read is a leak — confirm the destination first.
- **The lockfile's package manager differs from what's installed** (e.g. `pnpm-lock.yaml` but no `pnpm`). Surface the missing tool; don't silently fall back to `npm` and rewrite the lockfile.
- **The verify step fails for a reason that isn't missing config/deps** (a real compile error on the branch). That's the branch's problem, not the worktree's — report it, don't paper over it.
- **The repo ships its own bootstrap skill.** Stop and use it. A repo-specific one also handles things this generic skill omits — extra credential files, submodule init, worktree-config trust prompts, and lint hooks that run on push.

## Anti-patterns to avoid

- ❌ Committing `.env` / credentials "to fix the worktree permanently". They're gitignored because they're machine- or secret-specific — copy them, never track them.
- ❌ Authoring `.env` from memory. Copy it from a donor; a fabricated value that "looks right" fails silently later.
