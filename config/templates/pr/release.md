## 👥 Non-technical summary

<!--
    3–5 sentences someone outside this codebase could follow: what this batch
    changes for a reader of these files, not which PRs it contains. The PR list
    below is the inventory; this is the point.
-->

## 📐 Before / after

<!--
    MANDATORY for a release, even when a single PR in the batch needed no
    diagram. A release is the only place the accumulated shape change is
    visible: a reader who followed each PR still has not seen where the repo
    ended up.

    Show BEFORE, then AFTER, as two mermaid blocks, and highlight what is new:

      classDef new fill:#dcfce7,stroke:#16a34a,color:#166534;
      class NodeA,NodeB new;

    Draw what MOVED — a file's home, what loads what, what is scored and what
    is deliberately not. If a change genuinely moves no box (a bug fix inside
    one file, a CI timing fix), say so in a line under the diagrams rather than
    inventing nodes for it.
-->

## 📋 What changed

<!-- Grouped by theme, with the PR number against each. Not one bullet per commit. -->

## ✅ Test plan

<!--
    A release adds no commits, so its evidence is the state of the branch being
    promoted, not a fresh round of manual testing:

    - [ ] Every constituent PR was reviewed, CI-green and merged individually
    - [ ] Test suite on the head of `develop` (state the count)
    - [ ] Linters clean
    - [ ] Health check passes
    - [ ] `git diff <base> <head> --stat` reviewed — no unexpected paths
-->

## 🤖 Review

- [ ] Automated/AI review has run and its comments have been read
- [ ] Nothing is authored here — a release PR only moves reviewed commits
