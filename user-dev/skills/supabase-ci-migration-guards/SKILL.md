---
name: supabase-ci-migration-guards
description: >
  Use before writing or reviewing any migration that references Supabase-managed
  schemas — `auth.users`, `auth.uid()`, `storage.objects`, `storage.buckets`,
  `realtime.subscription`, `supabase_functions.*`, or any policy / function that depends
  on `auth.jwt()`. Auto-fire when a diff in `supabase/migrations/*.sql` matches the
  regex `(auth|storage|realtime)\.|to_regnamespace|create or replace function .*
  returns`. Also fire when the user says "fix the CI migration job" / "migration failed
  in CI" / "vanilla postgres errored on this migration" / "schema auth does not exist".
  Skip if the migration only touches the `public` schema with no Supabase-namespace
  references.
---

# Supabase-CI migration compatibility guards

CI runs migrations against vanilla Postgres (with bootstrapped `anon`/`authenticated`/`service_role`/`authenticator` roles but **no Supabase schemas**); production runs them against real Supabase. Any FK, policy, or function that references `auth.*` / `storage.*` / `realtime.*` blows up CI. The three failure modes:

- `ERROR: schema "auth" does not exist` — FK references `auth.users(id)`
- `ERROR: relation "storage.objects" does not exist` — RLS policy reads storage metadata
- `ERROR: cannot change return type of existing function` — `CREATE OR REPLACE FUNCTION` whose signature drifted

Each costs one fix commit + one CI cycle. The patterns below avoid all three.

## Procedure

### 1. Scan the migration

```bash
grep -nE '\b(auth|storage|realtime|supabase_functions)\.' supabase/migrations/<new>.sql
```

For every match, decide: does the referenced object exist in vanilla Postgres? If no, the migration needs a guard.

### 2. Guard FKs to `auth.users(id)` (and similar)

**Wrong** — fails in CI:
```sql
create table upload_jobs (
  id          uuid primary key default gen_random_uuid(),
  uploader_id uuid references auth.users(id) on delete set null,  -- ❌
  ...
);
```

**Right** — column unconstrained, FK bound conditionally at the bottom:
```sql
-- The FK to auth.users is added in a DO block so vanilla Postgres CI
-- (which has no `auth` schema) can apply the migration. Supabase
-- envs (prod + local dev) get the real FK.
create table upload_jobs (
  id          uuid primary key default gen_random_uuid(),
  uploader_id uuid,                                                -- ✅ unconstrained
  ...
);

do $$ begin
  if to_regnamespace('auth') is not null
     and to_regclass('auth.users') is not null then
    execute 'alter table upload_jobs
               add constraint upload_jobs_uploader_id_fkey
               foreign key (uploader_id) references auth.users(id)
               on delete set null';
  end if;
end $$;
```

The cost in vanilla CI: an unconstrained UUID column. Acceptable — the CI is testing schema validity, not referential integrity against Supabase data.

### 3. Guard policies that call `auth.uid()` / `auth.jwt()`

```sql
do $$ begin
  if to_regnamespace('auth') is not null then
    execute $POL$
      create policy "own rows only"
        on documents
        for select
        to authenticated
        using (owner_id = auth.uid())
    $POL$;
  end if;
end $$;
```

In CI the table exists with RLS enabled but no auth-aware policy — fine for schema-validity testing.

### 4. Guard reads of `storage.objects` / `storage.buckets`

Bucket creation isn't expressible in SQL anyway. Document it in the migration's header comment:

```sql
-- 🔔 Manual action (not expressible as SQL):
--   Create a Storage bucket named `uploads` in the Supabase dashboard.
--   PRIVATE, 50 MB cap recommended.
--   The server action writes via service-role; no anon access.
```

Then tag the maintainer in the PR body's "🔔 Manual action needed" section.

### 5. Handle `CREATE OR REPLACE FUNCTION` return-type drift

Postgres refuses `CREATE OR REPLACE` when the **return type** changes. If you redefine a function that's already on `develop` with a different signature, CI errors with `cannot change return type of existing function`.

In order of preference:

**(a) Don't redefine.** Add a sibling function under a new name (`search_entries_v2`), and deprecate the old one in a follow-up PR. External consumers stay on `v1` until they migrate.

**(b) Drop and recreate** — only if you're sure no external consumer depends on the old shape:
```sql
drop function if exists public.search_entries(text, text, text, int);

create function public.search_entries(...)
  returns table(...)
  language sql stable as $$ ... $$;
```
Use `cascade` only if you've confirmed dependents downstream.

**(c) Keep the signature, change only the body.** No drop, no return-type changes — pure body refactor. CI accepts this.

### 6. Smoke-test locally before pushing

Mirror the CI environment exactly:

```bash
docker run --rm --name pg-ci -e POSTGRES_PASSWORD=test -p 5432:5432 -d postgres:17

# Bootstrap the same roles CI does — see .github/workflows/ci.yml
psql "host=localhost user=postgres password=test" -c "
  create role anon;
  create role authenticated;
  create role service_role;
  create role authenticator;
"

# Apply migrations in order, stop on first error
for m in supabase/migrations/*.sql; do
  echo "Applying $m"
  psql "host=localhost user=postgres password=test" -v ON_ERROR_STOP=1 -f "$m" || break
done

docker stop pg-ci
```

If it passes locally, it passes in CI. ~30 seconds.

### 7. Document the guard in the migration header

Future maintainers reading the migration cold should see why the column is unconstrained / the policy is wrapped. A two-line comment at the top is enough:

```sql
-- This migration uses DO-block guards around `auth.users` references so
-- the CI vanilla-Postgres container can apply it. The real FK is bound
-- on Supabase envs only.
```

## When to STOP and ask

- The migration **depends on Supabase-seeded data** (e.g. an `auth.users` row with a specific UUID already exists). The guard pattern doesn't help — you need a pre-seed step or to restructure the migration.
- The `CREATE OR REPLACE FUNCTION` case is genuinely ambiguous because external API consumers may already depend on the old return shape. Pause, ask the user — dropping the function could break clients.
- The user explicitly says "this migration is Supabase-only, skip CI compatibility" — they may be running it only via `supabase db push` against the cloud. Confirm before omitting the guards.
- The project uses a non-Postgres dialect for CI (e.g. SQLite for fast tests) — the `to_regnamespace` probe doesn't exist there. Ask before adapting.

## Quick reference card

| Supabase reference | Guard pattern |
|---|---|
| `references auth.users(id)` | DO block + `to_regnamespace('auth')` |
| `using (auth.uid() = ...)` policy | DO block + `to_regnamespace('auth')` |
| `auth.jwt() ->> 'role'` in policy | DO block + `to_regnamespace('auth')` |
| `storage.objects` policies | DO block + `to_regnamespace('storage')` |
| Storage bucket creation | Manual dashboard step + header comment + @-maintainer in PR |
| `realtime.subscription` | DO block + `to_regnamespace('realtime')` |
| `create or replace function` w/ new return type | Rename to `_v2` OR `drop function if exists` first |

## Anti-patterns to avoid

- ❌ Adding the FK at table-creation time and "hoping CI passes" — it won't, you'll burn a fix commit.
- ❌ Using `to_regclass('auth.users') is not null` alone — if the schema itself is missing, the probe panics. Use `to_regnamespace('auth')` first.
- ❌ Wrapping the entire migration in `DO $$ begin ... end $$` — loses the per-statement error reporting that makes CI logs readable.
- ❌ `CREATE OR REPLACE FUNCTION` with a silent return-type change. Either rename the new one or drop the old one explicitly.
- ❌ Omitting the header comment that explains *why* a column is unconstrained — future maintainers will "helpfully" tighten it up and break CI again.
