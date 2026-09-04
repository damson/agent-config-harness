# Data Extraction agent guide

<!-- Single source of truth for this domain. AGENTS.md here is a symlink to this file; edit this one. -->

Preferences for extraction, scraping, ETL and ingestion work that differ from what you'd pick by default.

## Pipeline shape

```
fetch  →  parse  →  validate  →  transform  →  load
```

- Side effects live only at the ends. Parse / validate / transform are pure functions of the prior stage's output, testable without a network or a warehouse.
- One adapter per source in `adapters/<source_name>/`, exposing only `fetch()` and `parse()` plus its payload schema. Never extend an existing adapter to cover a second source.

## Validation

- Every record is a Pydantic (v2) model: no raw dicts past the parse stage.
- Validation errors are recorded, not raised: bad records go to a quarantine output, not the main sink.
- Schema drift is a hard failure: raise `SchemaDriftError` naming the added/removed fields. Never silently drop unknown fields.
- Contract tests re-run schema validation against a sample of real responses on a schedule; drift there fails the build.

## Idempotency

- Re-running an extraction over the same window yields the same result.
- IDs are deterministic, derived from source + business key. Not generated UUIDs.
- Cursors / watermarks live in a state table, not in code, not on the filesystem.

## Politeness

- Default to ≥ 1s between requests to the same host unless the source explicitly allows faster.

## Storage

- Write the raw response to immutable cold storage *before* parsing, so a parser fix can be replayed without re-fetching: `python -m pipeline.replay <source> <date>`.
- Partition by extraction date, never by load date.

## Language

- Python 3.11+ for extraction logic; TypeScript only for thin orchestration wrappers.
