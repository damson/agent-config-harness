---
name: capture-pr-screenshots
description: >
  Use when opening or updating a PR that changes a UI route file (`page.tsx`,
  `+page.svelte`, a `routes/` entry) without adding a matching screenshot. Also fire
  when the user says "missing screenshot" / "no screenshot for the UI" / "capture the
  screenshot" / "screenshot for this PR" / "you forgot the screenshot". Skip on a
  backend-only PR, or one that already includes screenshots for the surfaces it
  changes. Where the repo documents its own capture command, run that instead — this
  skill is the fallback for repos that document nothing.
---

# Capture PR screenshots end-to-end

From "the diff touched a UI page" to "the PR body shows a SHA-pinned image".

## Procedure

### 0. Defer to the repo's own command

```bash
{ find . -maxdepth 4 -iname '*screenshot*' -name '*.md'
  find . -maxdepth 4 -ipath '*screenshot*' -iname 'README*'; } 2>/dev/null | sort -u
```

If one exists and documents a regenerate/capture command, **run that and skip to step 7.**
It knows the project's viewport, auth story and naming. The steps below are defaults for
a repo that documents none of it.

### 1. Find the changed surfaces

```bash
BASE=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null \
       || git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|origin/||')
git diff "origin/$BASE"... --name-only | grep -E '(page|index)\.(tsx|jsx|vue)$|\+page\.svelte$|routes/.*\.(tsx|jsx)$'
SHOTS=$(find . -type d -iname 'screenshot*' -not -path './node_modules/*' | head -1)
echo "base=$BASE shots=${SHOTS:-<none>}"
```

Zero route matches, or no screenshot directory, means this repo is not shaped the way
this skill assumes — **stop and ask** rather than proceeding on empty results. Map each
route to a filename in `$SHOTS`, following the naming already used by the files there.

### 2. Pre-flight

- Ensure env files exist. In a secondary worktree they are gitignored and absent — link the primary's:
  ```bash
  MAIN=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
  ln -sfn "$MAIN/.env" .env.local        # adjust to the name the app reads
  ```
- Install at the repo root first; workspace layouts put binaries in the root `node_modules`.
- Find the auth-bypass variable rather than assuming a name:
  ```bash
  grep -rhoE 'process\.env\.[A-Z_]*(BYPASS|DEV_AUTH|SKIP_AUTH)[A-Z_]*' \
    --include='*.ts' --include='*.tsx' --include='*.js' . | sort -u
  ```
  Take the variable from the `process.env.X` hit. **More than one candidate: stop and
  ask** — guessing which gate the page honours is how you end up capturing the login form.

### 3. Start the dev server

```bash
export <BYPASS_VAR>=true          # export, not inline: an inline var may not reach the child
nohup npm run dev > /tmp/dev.log 2>&1 &
DEV_PID=$!                        # keep it: step 6 kills this, not whatever holds the port
disown
```

Read the port it actually bound, and bound the wait so a server that dies on startup
fails loudly instead of hanging:

```bash
PORT=""
for _ in $(seq 60); do
  kill -0 "$DEV_PID" 2>/dev/null || { tail -20 /tmp/dev.log; break; }   # it crashed
  PORT=$(grep -oE 'localhost:[0-9]+' /tmp/dev.log | head -1 | cut -d: -f2)
  [ -n "$PORT" ] && curl -sIL "http://localhost:$PORT" >/dev/null 2>&1 && break
  PORT=""; sleep 1
done
[ -n "$PORT" ] || { tail -20 /tmp/dev.log; echo "dev server never came up"; }
```

An empty `$PORT` after the loop means the server never came up — take the log tail to
the STOP list rather than capturing against nothing.

### 4. Capture each surface

```bash
CHROME=$(command -v google-chrome || command -v chromium \
         || echo "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
"$CHROME" --headless --disable-gpu --hide-scrollbars --window-size=1280,900 \
  --screenshot="$SHOTS/<surface>.png" "http://localhost:$PORT/<path>"
```

Match the viewport any existing screenshot uses; `1280×900` is only a default.

### 5. Verify the capture

Display each PNG with the Read tool. Reject and retry if it shows the login form (the
bypass never reached the server), a blank shell or error overlay, or an unstyled page
(CSS chunks had not compiled). **A screenshot of the login page is worse than none** —
it looks like evidence.

### 6. Stop the server

```bash
kill "$DEV_PID" 2>/dev/null || true
```

Kill the process this skill started, by pid. Killing whatever holds the port takes down
someone else's server when the port was already occupied.

### 7. Commit, then reference by SHA

```bash
git add "$SHOTS" && git commit -m "Add <surface> screenshot" && git push
SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PR=$(gh pr view --json number -q .number)
SHA=$(git rev-parse --short HEAD)          # after the commit that contains the image
```

**Pin to the SHA, never the branch.** A branch-pinned URL 404s forever once the branch
is deleted on merge. Edit the PR body in place rather than replacing it:

```bash
gh pr view "$PR" --json body -q .body > /tmp/pr-body.md
# append a row to the screenshots section:
#   | `/<surface>` | ![<surface>](https://github.com/$SLUG/raw/$SHA/<path-in-repo>.png) |
gh pr edit "$PR" --body-file /tmp/pr-body.md
```

## When to STOP and ask

- **Step 1 matched nothing** — no route files, or no screenshot directory. The repo is shaped differently; ask rather than guessing a layout.
- **The dev server will not start** — step 3's loop ends with an empty `$PORT`. Surface the log tail; do not push a half-baked image.
- **Step 2's grep returns more than one bypass variable.** Ask which gate the page honours.
- **The capture still shows the login page** after exporting the bypass variable. The block may be in middleware — confirm before weakening auth further.
- **The surface needs real data to mean anything** (an empty list view). Capture the empty state and say in the PR body that a populated variant follows.
- **No Chrome binary is found** by step 4's lookup. Ask how the browser is installed rather than guessing a path.

## Anti-patterns to avoid

- ❌ Capturing only the happy path when the page has error, empty or loading states a reviewer should see. Capture each meaningful state with a modifier suffix.
- ❌ Adding screenshots to a backend-only PR to fill the section. Omit the section instead.
