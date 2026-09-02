# Per-domain placeholder defaults

The portable template ([`pull-request-template.md`](pull-request-template.md)) has
exactly two `‹…›` slots, filled once at adoption time:

1. the **test command** in the ✅ Test plan section, and
2. the **repo-specific review gate** in the 🤖 Review section.

This file records sensible defaults for each registered domain so an adopter fills
them from a known-good starting point instead of guessing. It is **not** part of the
portable pair — it names stacks on purpose, which is why it lives here and not in the
template or the guide (both of which must stay vendor-neutral).

| Domain | ‹test command› | ‹repo-specific review gate› |
|---|---|---|
| `mobile` | `./gradlew testDebugUnitTest` (scoped: `:feature:<name>:testDebugUnitTest --tests "*Pattern*"`); `detekt` + `formatKotlin` clean | Screenshot baselines recorded **and** verified (Roborazzi); detekt/ktlint green in CI |
| `web-react` | `pnpm test && pnpm typecheck && pnpm lint` (Vitest + RTL) | `eslint-plugin-jsx-a11y` clean, no silenced warnings; Playwright E2E for new user flows |
| `backend-node` | `pnpm test && pnpm test:integration && pnpm typecheck` (integration needs Docker/Testcontainers) | New migration created for any schema change (never edit a shipped one); integration suite green |
| `data-extraction` | `pytest && ruff check && mypy --strict` | Contract/schema tests green (schema drift fails the build); fixtures scrubbed of real tokens |

Values are derived from each domain's `AGENTS.md` / `CLAUDE.md` "Build & Scripts" and
"Testing" sections — keep this table in sync if those change.
