# Design Review — M1: Database Abstraction Layer

Status: **AWAITING APPROVAL — no implementation until approved.**
Milestone: M1 (roadmap Track A). Depends on: M0. Everything that persists anything depends on this.

> Unfamiliar terms (public API, driver, migration, transaction, async/callback, parameterized query) are defined in [`docs/GLOSSARY.md`](../GLOSSARY.md).

## 1. Purpose

Provide the single way Omertà RP stores and retrieves data, so that:

- gameplay code never writes SQL and never learns which database is running;
- switching between SQLite and MySQL/MariaDB is one config value and **zero gameplay-code changes** (project-lead hard requirement);
- the schema can grow for years without rewriting earlier work;
- money, items, deaths, promotions, and evidence can be written atomically (Tech §22).

M1 builds the *mechanism*. It deliberately creates **no gameplay tables** — accounts belong to M2, characters to M4, and so on.

## 2. Responsibilities

**In scope:** connection lifecycle for both backends; an async query API identical across backends; a schema definition system that renders correct DDL per dialect; a versioned migration runner; transactions; result type normalization; query/error/slow-query logging; a readiness gate; an in-engine self-test.

**Out of scope:** any gameplay table or repository (each belongs to its own milestone); caching; sharding/read replicas; the archive-vs-season database split (Tech §22 — noted as a future extension in §9); admin UI over data (M24).

## 3. Public API

Everything lives under `Omerta.DB` and is **server-only** — the module is `sv_`, so it is never sent to clients.

```lua
-- Readiness. MySQL connects asynchronously, so nothing may query at load time.
Omerta.DB.WhenReady(fn)      -- runs fn() once connected AND migrated; immediately if already ready
Omerta.DB.IsReady()          -- boolean
Omerta.DB.Status()           -- { backend, connected, ready, queries, errors, lastError }

-- Schema and migrations. Declared at load time by each domain module.
Omerta.DB.DefineTable(name, definition)   -- see §4; name is unprefixed ("accounts")
Omerta.DB.AddMigration(version, name, fn) -- ordered, applied once, recorded

-- Queries. Called by repository modules only, never by gameplay directly.
-- Every callback receives (result, err); err is nil on success and never silently swallowed.
Omerta.DB.Query(sql, params, cb)      -- cb(rows, err)      rows is an array of row tables
Omerta.DB.QueryOne(sql, params, cb)   -- cb(row, err)       row is nil when nothing matched
Omerta.DB.Insert(table, row, cb)      -- cb(insertedId, err)
Omerta.DB.Upsert(table, row, keys, cb)-- cb(ok, err)        insert, or update when keys collide
Omerta.DB.Transaction(fn, cb)         -- fn(tx) queues tx:Query(sql, params); cb(ok, err)
```

`params` is always a separate array — the API accepts no other way to supply values (§7).

That is the entire surface. Two drivers sit behind it and neither is reachable from outside.

## 4. Data Model

M1 owns exactly one table, `omerta_migrations`: `version` (integer, primary key), `name`, `applied_at`.

It also defines the **schema DSL** every later milestone uses. Tables are declared in Lua with *logical* types, and each driver renders dialect-correct DDL:

```lua
Omerta.DB.DefineTable("accounts", {
    columns = {
        { name = "id",       type = "id" },                    -- auto-increment primary key
        { name = "steamid",  type = "text", length = 20, null = false },
        { name = "created",  type = "timestamp" },
        { name = "playtime", type = "int", default = 0 },
    },
    unique  = { { "steamid" } },
    indexes = { { "created" } },
})
```

Logical types: `id`, `ref` (foreign key), `text(length)`, `int`, `bigint`, `bool`, `timestamp`, `money`, `json`, `blob`.

This exists for three reasons, only the first of which is obvious:

1. **DDL differs** — `AUTO_INCREMENT` vs `AUTOINCREMENT`, `VARCHAR(n)` vs SQLite's dynamic typing, index syntax.
2. **Result types differ, and this is the dangerous one.** GMod's SQLite returns *every* column as a string; mysqloo returns real numbers and booleans. Without normalization, `row.playtime + 60` silently works on MySQL and misbehaves on SQLite — a bug that appears only after switching backends, which is exactly what the hard requirement exists to prevent. Because the DSL declares each column's logical type, the SQLite driver coerces results to match MySQL's typing. **Backend-identical return types are a guarantee of this layer, not a caller responsibility.**
3. **Table prefixing** — GMod's SQLite is one shared `sv.db` used by every addon on the server. All our tables get an `omerta_` prefix so we cannot collide with somebody else's `players` table. Callers pass unprefixed names; the layer applies the prefix.

## 5. Networking

**None.** M1 registers no net messages and sends nothing to clients. Database results reach players only through the systems built on top, each of which decides what that specific player is allowed to know. This is deliberate: it keeps the information philosophy (Tech §2 — never replicate what the observer hasn't earned) out of the data layer and in the gameplay layers where it belongs.

## 6. Persistence

This milestone *is* the persistence layer. Two drivers:

- **SQLite** — GMod's built-in `sql` library, storing in `garrysmod/sv.db`. Zero setup; the default for development and small servers.
- **MySQL/MariaDB** — the `mysqloo` binary module, loaded with a guarded `require`. If the backend is configured as MySQL and the module is missing, the server **fails loudly at boot** rather than silently falling back to SQLite and quietly writing a month of data into the wrong database.

Configuration, all server-scope so M0 guarantees it never replicates to clients:

| Key | Default | Notes |
|---|---|---|
| `db.backend` | `"sqlite"` | `sqlite` or `mysql` — the one value that switches everything |
| `db.host` / `db.port` | `"127.0.0.1"` / `3306` | MySQL only |
| `db.name` / `db.user` / `db.password` | — | MySQL only; credentials never leave the server |
| `db.table_prefix` | `"omerta_"` | |
| `db.slow_query_ms` | `100` | warn above this |
| `db.log_queries` | `false` | debug-level echo of every statement |

**Async on both backends, including SQLite.** GMod's `sql` library is synchronous, mysqloo is not. If the SQLite driver ran its callbacks inline while MySQL's arrived a tick later, code that accidentally depends on same-tick completion would work on SQLite and break on MySQL — again, the precise failure the requirement forbids. So **the SQLite driver defers its callbacks by one tick**, making completion timing behave the same on both. It costs nothing and removes an entire class of backend-specific bug.

**Migrations** run to completion before `WhenReady` fires. The runner applies pending versions in order, records each, and refuses to start if the database contains an applied version the current code does not know about (a downgrade — better to stop than to corrupt). One documented asymmetry: **MySQL DDL is not transactional** — it forces an implicit commit, so a failed migration cannot be rolled back the way SQLite can. Migrations are therefore written to be idempotent and resumable (`CREATE TABLE IF NOT EXISTS` and equivalents) rather than relying on rollback.

**Transactions** serialize their statements on one connection and report a single success/failure. SQLite uses `sql.Begin`/`sql.Commit`; MySQL uses mysqloo's transaction object. Failure rolls back where the backend permits and always reports the error.

**Connection health**: reconnect with exponential backoff; while down, queries queue up to a bounded limit rather than being dropped, because a game server silently discarding writes is worse than a brief stall. Exceeding the cap fails those queries loudly with an error passed to their callbacks.

## 7. Security Considerations

- **Injection is structurally impossible, not review-dependent.** The public API accepts values only as a separate `params` array. MySQL uses real prepared statements; SQLite — which has no parameter binding in GMod — escapes via `sql.SQLStr` inside the driver. There is no API that takes a pre-built string with values already in it, so no call site can get this wrong.
- **Credentials cannot leak.** They live in server-scope config, which M0 physically prevents from replicating, and the whole module is `sv_`, so it is never sent to clients.
- **No client input reaches SQL unvalidated** — the net layer (M0) validates types and bounds before any handler runs, and repositories add domain validation on top.
- **Server-only by construction**: the module refuses to load in the client realm.
- **Audit hooks**: every error and slow query is logged through `Omerta.Log`; the audit sink stub from M0 is where M2 will begin recording data-changing actions.

## 8. Dependencies

M0 only — config (credentials, backend selection), logging (diagnostics), and the module lifecycle. No third-party Lua libraries. `mysqloo` is an external binary module, required only when the MySQL backend is selected.

## 9. Future Extension Points

- **Repositories**: every later milestone adds its own (`modules/accounts/sv_repository.lua`, etc.), owning its SQL and exposing domain functions. Gameplay calls repositories; repositories call `Omerta.DB`.
- **Additional backends** (e.g. PostgreSQL) are a new driver behind the same public API.
- **Database split** (Tech §22's account / season / archive separation) becomes a second named connection — the API grows a connection argument with a default, without disturbing callers.
- Read replicas, query caching, and metrics all attach at the driver boundary.
- The schema DSL gains column types as needed (`decimal`, spatial) without touching call sites.

## 10. Architecture Rationale and Alternatives Rejected

**Why this shape:** the hard requirement is a statement about the public API, so the design puts everything backend-specific — dialect, typing, timing, escaping, transactions — behind a small surface (§3) and makes the drivers responsible for producing *identical observable behavior*, not merely "working."

**Rejected — a thin helper over `sql.Query` / mysqloo, with callers handling differences.** The cheapest option and the one that fails the requirement: dialect and typing differences leak into every call site, so switching backends means auditing all of them.

**Rejected — synchronous API modeled on SQLite.** Impossible for MySQL without blocking the server on network I/O, which freezes every player.

**Rejected — a full ORM / ActiveRecord layer.** Over-engineering for this project. It hides query cost, which matters in a game loop, and the modest gain over repositories does not justify the complexity or the maintenance burden across years.

**Rejected — existing GMod database libraries** (MySQLite, framework-bundled layers). The brief says build from scratch, and most of them paper over the sync/async difference by firing SQLite callbacks inline — the exact bug class §6 is designed to eliminate. Adopting one would also mean inheriting an external maintenance dependency at the foundation of a years-long project.

**Rejected — an `OnDatabaseReady` module lifecycle hook** in M0's loader. It would couple the generic module system to one specific subsystem. `Omerta.DB.WhenReady(fn)`, called from a module's `OnEnable`, achieves the same with the dependency pointing the right way.

## 11. Testing Strategy

**Headless** (`lua tests/run_tests.lua`, no engine): the decision-making logic is written as pure functions, as in M0 — DDL rendering for both dialects (string comparison against expected output), migration ordering and downgrade detection, parameter escaping, SQLite result-type coercion, the connection/queue state machine, and prefix application.

**In-engine**: an `omerta_db_selftest` console command running one suite — connect, migrate, CRUD, type-fidelity checks (a number written is a number read, on both backends), transaction commit, transaction rollback, injection attempt, and forced reconnect — against whichever backend is configured.

Because you have both backends available, the acceptance bar is: **flip `db.backend`, restart, run `omerta_db_selftest` again, and the identical suite passes unchanged.** That is the roadmap's M1 criterion, and it is the only real proof the abstraction holds.

## 12. Integration With Existing Systems

M1 is the first module: `modules/database/`, registered with `Omerta.Module.Register`, defining its config keys at load and connecting during `OnEnable`. Nothing in M0 changes. M2 (accounts) becomes the first consumer and the first repository, and its design review will show the pattern that every later milestone copies.

---

**Requesting approval to implement M1 as specified.** On approval: implementation, then the standard post-implementation report before M2's design review.
