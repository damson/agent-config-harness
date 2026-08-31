# CLI recipes

Command invocations worth looking up rather than memorising, for tools that are
not git (those live in [`git-recipes.md`](git-recipes.md)). Each entry exists
because the obvious invocation produces a subtly wrong result, not because the
command is hard to remember.

## HTML → PDF with headless Chrome

```bash
chrome --headless=new \
  --print-to-pdf=out.pdf \
  --no-pdf-header-footer \
  --print-to-pdf-no-header \
  "file://$(pwd)/file.html"
```

Two separate flags suppress two separate pieces of furniture, and dropping
either leaves the other in place:

| Flag | Removes |
|---|---|
| `--no-pdf-header-footer` | Chrome's own header and footer band |
| `--print-to-pdf-no-header` | the URL / date stamp printed into the margin |

The `file://` URL must be **absolute**, and getting that wrong exits `0`.
`file://probe.html` parses `probe.html` as a *host* rather than a path, so
Chrome renders its own `ERR_INVALID_URL` page — "This site can't be reached" —
into the PDF and reports success. The output is a valid, normal-sized PDF (in
one check, 59 KB against 9 KB for the real page, because the error page embeds
more fonts than the document did), so neither the exit status nor the file size
tells you anything. Verified against Chrome headless on macOS, 2026-08-29.

Check the render, not the exit code: `--screenshot=out.png` on the same URL
shows in one look whether Chrome loaded the page or its own error.

## `gh secret set` without a terminal

```bash
read -rs TOKEN && printf '%s' "$TOKEN" | gh secret set NAME --repo <owner>/<repo>
```

Run interactively, `gh secret set NAME` prompts for the value. Run anywhere
without a TTY — a script, a CI step, an agent shell — it reads **stdin instead of
prompting**, and an empty stdin stores an **empty secret**. It exits `0` and the
secret listing shows the name with a fresh timestamp, so the only symptom is
whatever consumes the secret failing later: for a token, an ordinary `401`,
indistinguishable from one that is invalid or revoked.

`read -rs` keeps the value off the screen and out of shell history, and piping it
gives `gh` real stdin to read.

**Diagnosing it after the fact:** print the length where the secret is consumed.
The length is not the secret and CI cannot mask it, and `0` versus `93`
distinguishes an empty secret from a bad one in a single line — nothing else does.

## Git credentials in a clone URL

```bash
# Rejected by GitHub, whatever the token:
git clone https://x-access-token:$TOKEN@github.com/owner/repo.git
# remote: Invalid username or token. Password authentication is not supported
# for Git operations.

# What works — the form actions/checkout uses:
auth=$(printf 'x-access-token:%s' "$TOKEN" | base64 | tr -d '\n')
git config --global http.https://github.com/.extraheader "AUTHORIZATION: basic $auth"
```

The error names a username and a password, so it reads as a credential-format
problem. It is not: GitHub refuses URL-embedded credentials for git operations
outright, and no token value makes that form work.
