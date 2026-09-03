## 👥 High-level summary

<!--
    3–5 sentences someone outside this codebase could follow. No identifiers,
    no file names, no jargon. Say what was true before, what is true now, and
    who is better off.

    Write this section LAST and FIRST-PERSON-FREE: if you cannot explain the
    change without naming a function, you may not yet understand its purpose,
    only its mechanism.

    Bad:  "Refactors PaymentAdapter to inject a RetryPolicy via the DI
           container, removing the hardcoded backoff."
    Good: "When a card payment failed because the bank was briefly
           unreachable, we gave up immediately and told the customer their
           card was declined, which wasn't true. Now we retry for a few
           seconds first. Customers stop seeing false declines, and support
           stops getting tickets about cards that actually work."
-->

<!--
    ═══ CONDITIONAL: KEEP ONLY IF THIS PR CHANGES HOW THINGS FLOW ═══
    Delete this whole block if no box or arrow moves: data path, request
    lifecycle, screen-to-screen navigation, build/deploy stage, state machine.
    A change in behaviour inside one existing box does NOT need a diagram.

## 📐 Before / after diagram

    Mermaid renders natively on GitHub and GitLab. Always show BEFORE, then
    AFTER, so the delta is visible rather than described.

    Before:
    ```mermaid
    flowchart LR
      Client --> API --> DB[(store)]
    ```
    After:
    ```mermaid
    flowchart LR
      Client --> API --> Queue[[queue]]
      Queue --> Worker --> DB[(store)]
      classDef new fill:#dcfce7,stroke:#16a34a,color:#166534;
      class Queue,Worker new;
    ```
    Highlight what is new with a class, so a reviewer sees the change without
    diffing two pictures by eye.
-->

<!--
    ═══ CONDITIONAL: KEEP ONLY IF A HUMAN CAN SEE THE DIFFERENCE ═══
    "Visible" is not only a browser. Keep this section for a web page, a
    mobile screen, a CLI's output, a generated report or export, an email,
    a dashboard panel, a log format someone reads on purpose.
    Delete it for pure internal refactors, infrastructure, or library work.

## 📸 Visible changes

    | Before | After |
    |---|---|
    | ![before](url) | ![after](url) |

    For a terminal or text-output change, paste the two outputs in fenced
    blocks instead of images; they diff better and survive forever.

    Host images so they outlive the branch: attach them to the PR (drag into
    the comment box) or reference a committed file BY COMMIT SHA, not by
    branch name, so the link does not break when the branch is deleted.

    For mobile: state device and OS version. A screenshot without them cannot
    be reproduced.
-->

## 📋 What changed

<!--
    Concrete changes grouped by component or layer. One bullet per decision a
    reviewer might question, not one bullet per file; the diff already lists
    the files.

    Include the reasoning for anything non-obvious, especially:
      - a road not taken, and why
      - a constraint that forced the shape of the change
      - anything that looks wrong but is deliberate

    A reviewer who has to reconstruct your reasoning will either reconstruct
    it wrongly or approve without understanding. Both are worse than a
    sentence you spend thirty seconds writing.
-->

## ✅ Test plan

<!--
    Evidence, not intentions. Every ticked box must name something you
    actually observed.

    - [ ] Automated checks pass: `bats tests/` and `shellcheck` (both run in CI)
    - [ ] New or updated tests cover the change (state the before → after count)
    - [ ] CI is green (name the jobs)
    - [ ] Verified end-to-end against real data or a running instance, not
          only at the unit boundary; say what you drove and what you saw

    RULES
    1. Never tick a box you did not verify. An honest `[ ]` with a one-line
       reason is worth more than a `[x]` that is aspirational; one
       fabricated tick makes every other tick unreliable.
    2. Numbers must be measured. "Improves performance" is not a test plan;
       "p95 3.2s → 0.4s over 500 requests" is.
    3. A green suite is not evidence when a test encodes the bug. If you
       changed or deleted a test, say why it was wrong.
    4. Docs- and config-only PRs still get a test plan: name the CI jobs and
       say what you checked the claims against. A document asserting a wrong
       number is that PR's failure mode.
    5. If a step could not be done, say so and why. Unknown-but-stated beats
       untested-and-implied.
-->

## 🤖 Review

<!--
    Adjust these three lines once at adoption time to match how this repo
    actually reviews, then leave them alone.
-->

- [ ] Automated/AI review has run and its comments have been read
- [ ] **Findings addressed or explicitly skip-justified after every push**: a
      new push invalidates the previous review; re-read it
- [ ] Statusline doc in sync: any change to `user-dev/statusline.sh` updates the
      "Statusline" section of `README.md` in the same PR

<!--
    RESPONDING TO REVIEW
    Reply on the PR itself, not only in a chat window; the audit trail has to
    live where the next person will look. One row per finding, with an
    unambiguous verdict:

      ✅ Applied:      landed in this push (cite file:line)
      🚫 Skipped:      will NOT be done (rationale required: false positive /
                       out of scope / intentional)
      ⏳ Deferred:     real, but not here (link the follow-up)
      💬 Acknowledged: for "this looks good" notes; no action

    Verify each finding against the source before acting on it. Automated
    reviewers read a diff without context and are confidently wrong often
    enough that applying findings unchecked will introduce bugs.
-->
