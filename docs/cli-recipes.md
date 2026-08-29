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
