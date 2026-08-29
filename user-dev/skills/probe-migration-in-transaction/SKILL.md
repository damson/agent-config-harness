---
name: probe-migration-in-transaction
description: >
  Use when a change adds or alters a SQL migration whose effect is a
  behaviour — an RLS policy, a view, a trigger, a grant, an enum, a constraint
  — and you want to know what it really does before opening the PR. Especially
  when there is no local Postgres: a transaction against the dev database that
  is rolled back costs nothing and leaves nothing. Do NOT fire for a bulk data
  write you intend to keep (that is reversible-bulk-write), for a migration
  that only adds a column nothing reads yet, or when the only database
  reachable is production.
---

# Probe a migration in a transaction

The deliverable is a role × capability matrix for the PR body.

## Procedure

1. **Name the invariant and record it before touching anything.** One count on
   the table the migration must *not* reach — `entries`, or whatever the change
   claims to leave alone. Step 6 re-reads it after the rollback; without the
   number beforehand, "did that touch anything?" has no answer.

   Probe rows seeded in step 4 are not a violation of this: they live and die
   inside the transaction. The invariant is about tables the migration should
   never have gone near.

2. **`begin`, then apply the file verbatim.** Read it from disk — never a
   retyped subset, or you have tested something the PR does not contain.

   ```js
   const sql = fs.readFileSync(migrationPath, 'utf8');
   await client.query('begin');
   await client.query(sql);          // the whole file, one statement to pg
   ```

3. **Assert the objects exist**, by catalogue rather than by absence of error —
   a `create` that silently did nothing raises nothing. Replace the names below
   with the ones the migration actually creates, read from its text:

   ```sql
   select
     (select count(*) from pg_type     where typname   = 'app_role')          as enums,
     (select count(*) from pg_class    where relname   = 'profiles')          as tables,
     (select count(*) from pg_proc     where proname   = 'app_role_at_least') as functions,
     (select count(*) from pg_policies where tablename = 'review_items')      as policies,
     (select count(*) from pg_trigger  where tgname    = 'on_auth_user_created') as triggers;
   ```

4. **Seed one account per role, insert at least one row per probed table, then
   impersonate.** The role is the whole point; the owner sees everything and
   proves nothing. The rows are not optional either — see the per-row sharp edge
   below. Both die with the transaction.

   ```sql
   set local role authenticated;
   select set_config('request.jwt.claim.sub', '<uuid>', true);
   ```

   Read the definition first rather than assuming which setting it consults —
   the wrong one silently yields an anonymous session that fails every check for
   the wrong reason:

   ```sql
   select pg_get_functiondef(oid) from pg_proc
    where proname = 'uid' and pronamespace = 'auth'::regnamespace;
   ```

5. **Wrap every probe query in its own savepoint** — not one per role, one per
   *query*:

   ```js
   async function ask(sql) {
     await client.query('savepoint q');
     try {
       const r = await client.query(sql);
       await client.query('release savepoint q');
       return { ok: r.rows[0] };
     } catch (e) {
       await client.query('rollback to savepoint q');   // without this, every
       return { err: e.message.split('\n')[0] };        // later query reports
     }                                                   // the abort, not itself
   }
   ```

6. **Roll back, then prove it.** Put the rollback in a `finally` so a thrown
   probe cannot leave the transaction open, then re-run step 3's count and
   assert it is back to zero, and re-check step 1's invariant.

   ```js
   } finally {
     await client.query('rollback');
     // and assert: the catalogue count from step 3 is 0 again
   }
   ```

7. **Report the matrix, not the verdict.** Derive the columns from the
   migration itself — one per statement that changes what someone may do:
   a `create policy ... for select` becomes a read column, `for update` a write
   column, each masked expression in a view a column of its own, and every
   `revoke` a column asserting the bypass is shut. Rows are the roles, lowest
   and highest always included. One unit per column — row counts throughout,
   with `refused` reserved for a statement that raised:

   | role | read | write | privileged column | direct table access |
   |---|---|---|---|---|
   | `pending` | 0 rows | 0 rows | NULL | refused |
   | `volunteer` | 2,398 rows | 0 rows | NULL | refused |
   | `admin` | 2,398 rows | 1 row | visible | refused |

   A write permitted that matched zero rows is a different answer from one
   refused: the first says the policy filtered every row, the second says the
   grant held before the policy was ever consulted. Collapsing them into one
   ✅/❌ column loses which mechanism you are relying on.

   The last column is the one people omit: a matrix without it proves the front
   door is locked and says nothing about the window.

8. **Break it on purpose, in a second transaction.** Strip the marker the
   migration relies on — `security definer`, a `where` clause, a `case when` —
   apply the mutated text, and confirm the probe that passed now fails. An
   assertion never observed failing is decoration. Same discipline as
   `prove-the-check-can-fail`.

   ```js
   const broken = sql.replace('  security definer\n', '');
   if (broken === sql) throw new Error('the strip did nothing — wrong marker');
   await client.query('begin');
   try {
     await client.query(broken);
     // and assert: the probe that passed in step 5 now fails
   } finally {
     await client.query('rollback');           // step 6's discipline, again:
     // and assert: step 3's catalogue count is 0 again
   }
   ```

9. **If application code reads the new objects, replay its queries too.** Find
   the readers rather than guessing at them: grep the repo for each name the
   migration creates, taken from its text.

   ```bash
   rg -n 'review_items|app_role_at_least' --type ts
   ```

   Then replay every select list, filter and order found at those call sites,
   inside the same transaction. A column the view does not expose is a 500 at
   runtime and nothing in the type system sees it.

## Sharp edges

Each of these produces a **green that means nothing**, which is worse than a
failure.

- **A shared savepoint fabricates refusals.** One `permission denied` aborts
  the transaction, so every later query in that savepoint answers
  `current transaction is aborted` — which tabulates as "refused" and looks
  exactly like the result you were hoping for. This is why step 5 is per query.

- **An RLS qual is evaluated per row, so an empty table tests nothing.** A
  policy over zero rows is never invoked: the correct version and the broken
  one both pass, for the same uninteresting reason. Insert a row first, then
  probe.

- **A view with `security_invoker = false` — the default — bypasses RLS on its
  base tables.** If the migration adds one, the row rule must be restated
  inside the view, and the probe must confirm it: a masking view that forgot it
  hands every row to every caller while looking like a tightening.

- **Nulls and refusals are different answers.** A masked column returns NULL; a
  revoked grant raises. A probe that reports both as "hidden" cannot tell you
  which mechanism is actually holding.

## When to STOP

- **The only reachable database is production.** Transactional or not, do not.
- **The migration is destructive** (`drop`, `truncate`, a narrowing type
  change). Rolling back your probe does not make the migration safe; that needs
  the repo's destructive-op review.
- **Applying it is the maintainer's step.** Probing is not applying, and the
  distinction must survive into the report: say the migration is unpushed.
- **The behaviour needs a real request** — a page reading a view, an auth
  callback. A transaction cannot cover it. Say so plainly rather than implying
  end-to-end coverage you do not have.
- **The probe would write anything that outlives it.** If you cannot express
  the check inside `begin`/`rollback`, it is a different task with a different
  gate.
