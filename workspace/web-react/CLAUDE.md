# Web (React) — agent guide

<!-- Single source of truth for this domain. AGENTS.md here is a symlink to this file; edit this one. -->

Preferences for React / Next.js work that differ from what you'd pick by default.

## Architecture

- Feature folders, not type folders: `features/checkout/CartSummary.tsx`, not `components/CartSummary.tsx`. Co-locate the component with its test and its styles.
- Cross-component state: prefer URL state (search params) before context, context before a store. Global mutable store is Zustand where the team already uses it — no Redux in new code.
- Server state: TanStack Query or RSC fetch. Never roll your own cache.
- RSC `fetch` always names its `cache` / `next.revalidate` option — an unstated caching policy is the bug, in either direction.

## Design quality

- Invoke the `impeccable` skill before building or restyling a surface. Prefer it over the `frontend-design` plugin skill here — don't run both on the same task.
- `/impeccable init` writes the `PRODUCT.md` and `DESIGN.md` brief the skill reads on every later run. Once per project, not per feature.
- Its design detector hook is per project *and* per machine: `npx impeccable install` writes it to the gitignored `.claude/settings.local.json`, so a teammate's clone has no hook until they run it too.

## Testing

- Naming: `describe('<ComponentName>', ...)` and `it('renders <state>', ...)` — no `should`.
- Query by role/label/text, not test-id.

## Performance

- Memoize selectors, not components, by default.

## Editing discipline

- More than 5 props on a component means extract sub-components or take `children`.
- Don't add a dependency without checking the existing stack first (no `axios` where `fetch` is used everywhere).
- When refactoring, change only lines inside the function/component you're touching. Don't reformat or rename across the file.
