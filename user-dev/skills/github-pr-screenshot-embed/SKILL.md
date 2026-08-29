---
name: github-pr-screenshot-embed
description: >
  Use when embedding a screenshot or image in a GitHub PR description or comment,
  especially for a PRIVATE repo. Fire when the user says "the screenshot is a
  broken image in the PR", "embed this in the PR", "the image doesn't render for
  reviewers", "add a before/after image to the PR", or when a
  raw.githubusercontent.com link shows as a broken image. Skip for GitLab MRs —
  GitLab rewrites uploaded paths differently and needs its own upload step.
---

# Embed screenshots in a GitHub PR (private repos)

Private-repo image embeds break in one specific, silent way: the image host you
pick decides whether the browser can authenticate. Get the host wrong and every
reviewer sees a broken-image icon while the link looks correct to you (your
browser is already authenticated).

The rule: **use `github.com/<owner>/<repo>/raw/<sha>/<path>`, pinned to a commit
SHA.** GitHub serves that host with browser cookies, so anyone with repo access
renders it; it leaves both image hosts un-proxied, so the browser fetches
directly.

## Procedure

### 1. Commit the image into the PR branch

Commit the screenshot into the repo (e.g. under `docs/screenshots/`) on the PR
branch and push. You need its path and the **commit SHA** that contains it:

```bash
git rev-parse HEAD   # the SHA to pin
```

Do not rely on the branch name in the URL (see step 3).

### 2. Build the embed URL

```
https://github.com/<owner>/<repo>/raw/<sha>/<path-to-image>
```

Use it in standard markdown in the PR description or comment:

```markdown
| Before | After |
|---|---|
| ![before](https://github.com/OWNER/REPO/raw/<sha>/docs/screenshots/before.png) | ![after](https://github.com/OWNER/REPO/raw/<sha>/docs/screenshots/after.png) |
```

**Never use `raw.githubusercontent.com`** for a private repo. That host is
token-authenticated only and never receives browser cookies, so the embed is a
broken image for every reader even though it resolves for you via a token.

### 3. Pin the SHA, never the branch

Use the commit SHA in the path, not the branch name. A squash-merge deletes the
branch, which 404s every branch-pinned URL — but the PR's head commit stays
reachable via `refs/pull/<n>/head` indefinitely, so a SHA-pinned embed survives.

### 4. Verify as a different reader

Open the PR in an incognito window (or ask a reviewer). A broken image here is
the wrong-host signal — re-check that the URL is `github.com/.../raw/...` and not
`raw.githubusercontent.com`.

## When to STOP and ask

- The screenshot shows real customer data, real balances, KYC documents, or auth
  tokens. Committing an image into a repo is a durable publication — surface the
  concern and propose a redacted re-capture before committing.
- The repo is public and you were about to over-engineer: a plain committed image
  or a drag-and-drop attachment is fine; this skill's host nuance only matters for
  private repos.
- The user wants a drag-and-drop attachment via `gh`. It is not possible — the
  `POST /upload/policies/assets` endpoint 422s without a real browser session, so
  the attachment CDN is unreachable from the CLI. Commit the image and reference it
  by SHA instead.
