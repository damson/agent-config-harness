# Mobile — project layer (example)

<!-- EXAMPLE DOMAIN. Replace with your project's real rules, or delete the
     domain from config/domains.conf. This layer holds what the TEAM agrees;
     personal preferences go in ../CLAUDE.md. -->

Kotlin / Android, Gradle with version catalogs, Hilt for injection.

## Commands

| Task | Command |
|---|---|
| Unit tests for one module | `./gradlew :feature:<name>:testDebugUnitTest` |
| One test class | add `--tests "*<Pattern>*"` |
| Screenshot baselines | `./gradlew :feature:<name>:verifyRoborazziDebug` |
| Re-record baselines | `./gradlew :feature:<name>:recordRoborazziDebug` |
| Static analysis | `./gradlew :<module>:detekt` |

## Architecture

- Feature modules depend on `:core`, never on each other. **A cross-feature
  import means the code moves to `:core` before the PR opens** — do the move,
  do not raise it as a comment.
- Every interface-backed use case needs a `@Binds` entry in its feature module.
  A missing binding **compiles locally and fails only the full graph in CI**, so
  the local build passing is not evidence.

## Testing

- Every screen has a screenshot test covering its main states, capturing the
  `@Preview` functions rather than rebuilding the composables — a preview cannot
  then go stale without a baseline changing with it.
- Unit tests do not touch the network. Anything that does is an integration test
  and runs in its own Gradle task.

## Git

- Branch from `develop`; `main` carries releases only.
- One logical change per commit. Squash fixups before review.
