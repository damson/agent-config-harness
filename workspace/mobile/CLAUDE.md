# Mobile personal layer (example)

<!-- EXAMPLE DOMAIN. Personal overrides on top of project/CLAUDE.md beside this
     file. Team-agreed rules belong there; `just eval` scores each layer alone. -->

## Code

- Max 25 lines per method for ordinary business logic. Past that, extract.
- No bare abbreviations in names: spell them out. An abbreviation is acceptable
  only as a suffix on an already-explicit name (`healthyMaxRatio`, never `hmr`).
- Boolean fields name their subject so the negation still reads: prefer
  `isPaymentEnabled` over a bare `isEnabled`.
- Small pure helpers are extension functions. Anything with an injected
  dependency, or that a caller needs to mock, is a use case.

## Reviews

- Screenshot diffs go in the PR description, not a comment: a comment scrolls
  away and the description is what a reviewer opens first.
- Reply to every review finding with one of: applied, skipped with a reason, or
  deferred with a link. Never "noted".
