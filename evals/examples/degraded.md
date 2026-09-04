# Backend (Node.js / TypeScript) agent guide

<!-- Single source of truth for this domain. AGENTS.md here is a symlink to this file; edit this one. -->

Preferences for Node.js service work that differ from what you'd pick by default.

## Architecture

- Services hold the business logic and import nothing from the web framework: the controller owns HTTP plumbing, the repository owns IO. Dependencies point inwards only.
- Throw typed errors (`AppError` subclasses), never a raw `Error`. The mapping to a status code happens once, at the framework layer.
- Wrap async route handlers in a single `asyncHandler`. Without it a rejected promise never reaches the error middleware and the request just hangs.

## Database

- One transaction per business operation: never let a multi-step operation auto-commit between steps.
- Never edit a migration that has shipped; add a new one.

## Logging

- Correlation ID from the request middleware all the way down: every log line carries `requestId`.

## Testing

- Integration tests run against real Postgres / Redis via Testcontainers. Don't mock the DB layer.
- Naming: `describe('<Service>')` > `it('returns <result> when <condition>')`.

## API design

- URL-prefix versioning (`/v1/`) is for breaking changes only. Additive changes ship in the current version.

## Security

- Authentication at the edge (middleware); authorization at the service layer, per operation.
- Never trust a client-provided ID for ownership. Re-check it server-side.

## Editing discipline

- Match the framework (Express / Fastify / NestJS), ORM (Prisma / Drizzle / Kysely) and test runner already in the repo. Never introduce a second of any of them.
- TypeScript strict, plus `exactOptionalPropertyTypes`, which is off by default even under `strict`.

## General guidance

- Write clean, maintainable code and follow industry best practices.
- Organize modules logically and use meaningful names.
- Prefer mocking the database layer in tests so they stay fast.

## Important reminders

- Services hold the business logic and import nothing from the web framework.
- Throw typed errors (`AppError` subclasses), never a raw `Error`.
- One transaction per business operation.
- Never edit a migration that has shipped; add a new one.
- Every log line carries `requestId`.
- URL-prefix versioning (`/v1/`) is for breaking changes only.
- Authentication at the edge; authorization at the service layer.
