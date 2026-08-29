---
name: pr-comment-loop
description: >
  Use when an active branch has open PRs that may have received new comments since the
  last check. Auto-trigger after any `git push` to a feature branch, after merging a PR
  (other open PRs may need rebase + re-review), and any time the user asks "is PR N
  ready?" / "what's the status of PRs?" / "manage the open PRs" / "anything to address
  in PR N?" / "review the comments". Skip if no PRs are open or if the user explicitly
  says "ignore the comments".
---

# PR comment loop

After every push to a feature branch (or any time you're asked to take stock of open PRs), close the loop on AI-reviewer and human comments instead of waiting for the user to ask.

## Procedure

For each open PR you have touched in this session — OR all open PRs in the current repo if no explicit list:

1. **Snapshot state**:
   ```bash
   gh pr view <n> --json mergeable,mergeStateStatus,statusCheckRollup,comments,baseRefName
   ```

2. **Identify NEW comments** since your last reply on that PR. Compare comment `createdAt` (from `gh pr view --json comments,reviews`) against the timestamp of the latest sticky reply comment you posted (the one with `<!-- claude-review-response -->` — find it with the safe selector in step 6). If none exists yet, treat every comment as new.

3. **Verify each finding against the source, then classify it.** Before acting on a finding, open the cited `file:line` in the actual source. Cold-read reviewers see the diff without surrounding context and are confidently wrong often enough that applying findings unchecked introduces bugs — real examples: a missing guard reported that already existed six lines above the hunk; an empty array literal misread as a JSON object, predicting a constraint violation no constraint could produce; a changelog entry demanded in a repo with no changelog; a finding re-raised in round 4 that was applied in round 1. A finding that does not survive that check gets a 🚫 Skipped row (verdict vocabulary in step 6) citing the contradicting line — never silence.

   Then parse the comment body (`.comments[].body` and `.reviews[].body` from the JSON above) for emoji headings `🔴 Critical`, `🟡 Should fix`, `🟢 Nice to have`. If the reviewer doesn't use that emoji convention, treat the entire comment as a single 🟡 finding and surface it to the user before classifying.

   | Severity | Default action | Rule |
   |---|---|---|
   | 🔴 Critical | Apply | Skip only if file paths cited are in directories untouched by this PR — then defer with a follow-up issue link |
   | 🟡 Should fix | Apply | Skip if the finding is a false positive (cite the contradicting code / spec line) or if it blocks PR scope (cite the scope boundary) |
   | 🟢 Nice to have | Apply if diff ≤ 10 lines AND ≤ 1 file | Otherwise defer with a follow-up issue link |
   | ✅ Acknowledgement | No code action | Reference in the reply table only |

4. **Apply fixes** via a single commit per PR with a body that:
   - References the AI review's structure (numbered findings)
   - States explicitly "🚫 Skipped #N: <reason>" for non-applied findings (same label as the verdict table) — silence on a finding is forbidden by the project's "re-read after every push" convention

5. **Push + verify**:
   ```bash
   git push
   gh pr view <n> --json mergeable,mergeStateStatus
   # confirm CLEAN before reporting back
   ```

6. **Post a reply comment on the PR.** The audit trail of "comment seen, classified, addressed" must live on GitHub — a reply in the Claude session does NOT count. Use sticky-comment style (`<!-- claude-review-response -->` marker → upsert) so re-runs don't spam the PR — **one comment per PR, edited in place across rounds, never a new one each round.**

   ### Finding the sticky comment safely

   The upsert overwrites whatever it selects, and does so silently — so the selector must be exact. Three traps, all hit for real:

   - **Match the marker with `startswith`, never `contains`.** An automated reviewer that *quotes* your marker — because it is reviewing the very diff that introduced it — matches a `contains` filter, and you overwrite the review.
   - **Exclude the reviewer's own account** from the candidate set, identified by author login, so the filter can only ever select your own comment.
   - **Count the matches and abort unless exactly one.** Patch the single match; if zero, post fresh; if more than one, stop and surface it. Overwriting the wrong comment raises no error.

   ```bash
   marker='<!-- claude-review-response -->'
   me=$(gh api user -q .login)
   # MY comments whose body STARTS WITH the marker — never `contains`, never the reviewer's
   mine=$(gh pr view <n> --json comments \
     --jq "[.comments[] | select(.author.login == \"$me\" and (.body | startswith(\"$marker\")))]")
   case "$(jq length <<<"$mine")" in
     0) : "post a fresh comment" ;;
     1) : "PATCH that one comment (edit in place)" ;;
     *) : "STOP — more than one match, do not patch" ;;
   esac
   ```

   The marker is machine-written — never hand-type it into a comment.

   ### Verdict vocabulary — use these labels EXACTLY

   | Verdict | When to use | Rationale required? |
   |---|---|---|
   | ✅ **Applied** | The fix landed in the same push. Cite the file + line. | No (action column shows the change) |
   | 🚫 **Skipped** | The finding will NOT be addressed — neither now nor later. | YES — one-line reason (false positive, out of scope, intentional design, etc.) |
   | ⏳ **Deferred** | The fix is real but not landing in this PR. | YES — link the follow-up issue / PR / TODO marker |
   | 💬 **Acknowledged** | ✅-style "what looks good" notes from the reviewer. No action expected. | No |

   Forbidden: vague verdicts like "Considered", "Noted", "Reviewed",
   "Justify-skip" (use 🚫 Skipped with reason instead). The whole point
   is unambiguity.

   ### Template

   ```markdown
   <!-- claude-review-response -->
   ## ✏️ AI-review response (PR #N)

   | Finding | Verdict | Action / rationale |
   |---|---|---|
   | 🟡 #1 <short title> | ✅ Applied | <file:line + one-line summary> |
   | 🟡 #2 <short title> | 🚫 Skipped | <one-line reason — false positive / scope / intentional> |
   | 🟢 #3 <short title> | ⏳ Deferred | <follow-up reference> |
   | ✅ #4 <short title> | 💬 Acknowledged | — |

   Pushed as `<sha>`.
   ```

   Post via `gh pr comment <n> --body "$(cat <<'EOF' ... EOF)"`. Even when every finding is 🚫 Skipped with no code change, still post the reply.

   ### Recovering a clobbered comment

   If you do overwrite the wrong comment, GitHub retains every prior body — recover it before anything else. REST does not expose this; GraphQL does:

   ```bash
   gh api graphql -f query='
   { repository(owner:"OWNER", name:"REPO") { pullRequest(number:NN) {
       comments(first:20) { nodes { databaseId
         userContentEdits(first:20) { nodes { editedAt editor { login } diff } } } } } } }'
   ```

   `userContentEdits` returns prior bodies newest-first. Take the last one written by the original author, write it to a file, and restore with `gh api -X PATCH repos/OWNER/REPO/issues/comments/<id> -F body=@restore.md`. Then post your own reply as a **separate** comment.

7. **Report back to the user** with a single line per PR:
   ```
   PR #N: <m> findings addressed, <k> skip-justified, reply posted, <state>
   ```

## When to STOP and ask

- An 🔴 finding's fix is non-trivial AND ambiguous (would require a design call).
- A finding contradicts an earlier decision in the session — surface the contradiction before re-litigating.
- All CI checks are red and root cause isn't obvious — don't push speculative fixes.
- Test count drops vs the previous push — surface this before continuing.
- Never close or merge the PR from this skill — that is always the user's call.
