# Design Review — M2: Accounts and Audit Foundation

Status: **AWAITING APPROVAL — no implementation until approved.**
Milestone: M2 (roadmap Track A). Depends on: M0, M1. Consumed by: M3 (seasonal path per account), M4 (characters belong to accounts), M24 (admin tooling), and every system that audits anything — which is all of them.

> Terms are defined in [`docs/GLOSSARY.md`](../GLOSSARY.md). This milestone introduces the first **repository** — the pattern every later data-owning milestone copies.

## 1. Purpose

Two things, deliberately bundled because they share the first real migration:

1. **Accounts**: every connecting player gets a persistent record keyed by SteamID64 (Tech §2 Account) — created on first join, loaded on every join, carrying first/last seen, playtime, connection count, moderation flags, and a career-statistics skeleton. This is the anchor everything else hangs off: characters (M4), seasonal path (M3), cosmetics and titles (later, per Tech §22 account persistence).
2. **Audit persistence**: M0's `Omerta.Log.Audit` stub starts writing its envelopes to the database (Tech §23). Call sites do not change — that was the stub's contract. From M2 on, every milestone's sensitive actions are queryable history, which the hidden-identity design makes non-negotiable: staff cannot see cheating that leaves no trail.

## 2. Responsibilities

**In scope:** accounts table + repository; account flags and career-stat counter tables; audit table; **migration 1** (the first real migration — M1's runner finally earns its keep); connect flow (load-or-create, cache on the player); disconnect flow (last-seen, playtime); periodic playtime flush so crashes lose minutes, not sessions; audit retention cleanup; an in-engine self-test.

**Out of scope:** seasons and path selection (M3), characters (M4), cosmetics/titles content and their tables (added by their own migrations when their systems exist), any admin/staff UI (M24), any client-facing UI, bans as a mechanism (flags store moderation *state*; enforcement policy is a rules/M24 concern).

## 3. Public API

Server-only, like everything touching the database.

```lua
-- Accounts (module: modules/accounts/)
Omerta.Accounts.Get(ply)                  -- cached account table, or nil before load completes
Omerta.Accounts.IsLoaded(ply)             -- boolean
Omerta.Accounts.GetBySteamID64(sid64, cb) -- cb(account, err) — offline lookup, no caching

Omerta.Accounts.SetFlag(ply, flag, reason, actorSid64, cb)  -- audited
Omerta.Accounts.ClearFlag(ply, flag, actorSid64, cb)        -- audited
Omerta.Accounts.HasFlag(ply, flag)        -- from cache, synchronous

Omerta.Accounts.AddStat(ply, stat, delta) -- atomic counter increment, fire-and-forget
Omerta.Accounts.GetStat(ply, stat)        -- from cache, synchronous

-- Extension point: gamemode hooks, the standard GMod idiom
hook.Run("Omerta.AccountLoaded", ply, account)     -- after load-or-create completes
hook.Run("Omerta.AccountUnloading", ply, account)  -- before disconnect finalization
```

The account table handed out is a **read-only snapshot by convention** — mutations go through the API so they persist and audit. (Enforcing immutability with metatables is deliberately skipped: cost without benefit in trusted server code.)

**One addition to M1's database API** (extension point exercised, not a redesign):

```lua
Omerta.DB.UpsertIncrement(tableName, keyRow, counter, delta, cb)
-- INSERT .. ON CONFLICT/ON DUPLICATE KEY UPDATE counter = counter + delta
```

Needed because `Upsert` sets literal values, while career stats and future counters (treasury tallies, heat) need atomic read-free increments. It renders per dialect inside the DB layer, keeping dialect knowledge out of repositories — the exact boundary M1 exists to hold.

## 4. Data Model

Migration 1 creates four tables via the M1 schema DSL:

```lua
accounts:        id(id), steamid64 text(20) NOT NULL, first_seen timestamp, last_seen timestamp,
                 playtime int DEFAULT 0 (seconds), connections int DEFAULT 0
                 unique(steamid64)
account_flags:   account_id ref, flag text(32), set_at timestamp, set_by text(20), reason text(255)
                 primary(account_id, flag)      -- composite key: one row per flag per account
account_stats:   account_id ref, stat text(32), value bigint DEFAULT 0
                 primary(account_id, stat)      -- generic counters, data-driven stat names
audit:           id(id), at timestamp NOT NULL, event text(64) NOT NULL,
                 actor text(20), subject text(20), data json
                 indexes: (event), (actor), (at)
```

Why relational flags/stats instead of JSON blobs on the account row: staff queries ("every account flagged X", "top robbery counts") stay SQL; increments stay atomic; and there is no read-modify-write race when two systems touch the same account in the same tick. JSON on the audit `data` column is fine because audit rows are write-once and searched by the indexed columns, not by their payload.

Career stats are **counters only, by name** (`"robberies_completed"`, `"cases_closed"`): systems invent names as they arrive, no migrations per stat. Tech §2's cosmetics/titles/seasonal-history live in future tables owned by their own milestones — created empty now they would only fossilize guesses.

## 5. Networking

**None.** No net messages, nothing replicated. A client learns nothing about any account in M2 — including its own (there is no UI to show it). Later milestones replicate the minimum a client needs about *itself*, never about others; starting from zero keeps the information-philosophy default intact.

## 6. Persistence

- **Connect**: on `PlayerInitialSpawn`, the repository load-or-creates by `ply:SteamID64()` inside `Omerta.DB.WhenReady`, bumps `connections` and `last_seen`, caches the account on the player, fires `Omerta.AccountLoaded`, audits `account.connect`.
- **The gate**: until the load completes, the player has no account and later systems must treat them as inert (`IsLoaded` is the check; M4 will hold such players in its character flow anyway). If the load errors or exceeds `accounts.load_timeout` (default 15s), the player is **kicked with a clear message** — a server that cannot persist must not quietly accept players, the same fail-loudly stance as M1's missing-backend boot error. Configurable off (`accounts.kick_on_failure = false`) for local development only.
- **Disconnect**: playtime accumulates, `last_seen` updates, `account.disconnect` audits, cache clears.
- **Crash insurance**: a periodic flush (default every 300s, config) writes playtime/last_seen for everyone online, so a crash loses minutes.
- **Audit**: `Omerta.Log.Audit` keeps its exact M0 envelope and console line, and additionally inserts the envelope into `audit` (actor/subject promoted to columns, remainder JSON-encoded into `data`). Write-per-event for now — volumes are trivial until crime systems arrive; batching is a documented extension, not speculative code.
- **Retention**: `audit.retention_days` (default 0 = keep forever) with a cleanup pass at boot and every 6 hours. Seasonal archiving (Tech §22) will revisit retention when M23 exists.

Config keys (all server scope): `accounts.load_timeout`, `accounts.kick_on_failure`, `accounts.flush_interval`, `audit.retention_days`.

## 7. Security Considerations

- Identity comes exclusively from `ply:SteamID64()` server-side — no client input exists anywhere in this milestone (no net messages at all).
- Audit rows are **append-only**: no API updates or deletes them except the retention sweep; flag changes are themselves audited with the acting staff member's SteamID64.
- The connect gate means an unpersistable server rejects players rather than running ghost sessions that would violate the audit guarantee.
- Cached accounts are server memory only; nothing replicates (§5).

## 8. Dependencies

M0 (module lifecycle, config, log, hooks), M1 (`WhenReady`, `Query`/`Insert`/`UpsertIncrement`, migration runner). No new binaries, no third-party code.

## 9. Future Extension Points

- The two hooks are where M3 (path selection on load) and M4 (character menu on load) attach.
- Flags and stats are name-driven: new systems add names, not schema.
- Cosmetics, titles, seasonal history: future tables + migrations keyed on `account_id`.
- Audit batching, an audit query API, and the staff UI all land in M24 against this table unchanged.
- `UpsertIncrement` serves every future counter (department funding, heat, respect/fear tallies).

## 10. Architecture Rationale and Alternatives Rejected

**Why bundle accounts with audit:** they share the migration, and audit-without-actors is half a feature — `account.connect` is the first event worth recording, and every later event's `actor` column is a SteamID64 this table gives meaning to.

**Rejected — JSON blobs for flags/stats** (see §4): unqueryable and race-prone; the relational cost is two small tables.

**Rejected — letting unloaded players play**: a player who acts before their account exists produces unauditable actions and lost stats; the gate is cheap and M4 needs it anyway.

**Rejected — a permissions/roles system now**: tempting to build "moderation" fully, but enforcement policy belongs to rules + M24 tooling; M2 stores state only.

**Rejected — per-stat columns**: every new stat would be a migration; the counter table makes stats data, matching how item definitions and config keys already work in this codebase.

## 11. Testing Strategy

- **Headless** (extends the existing suite): repository logic against the M1 mock driver — load-or-create both paths, flag set/clear SQL, `UpsertIncrement` rendering on both dialects, audit envelope→row mapping, playtime accumulation math (pure), retention cutoff math (pure).
- **In-engine**: `omerta_accounts_selftest` (same pattern that just proved itself): synthesizes an account by fake SteamID64, loads it back, sets/clears a flag, increments a stat twice and reads the sum, writes an audit event and reads it back, then deletes its synthetic rows. Plus the lived test: joining the server logs the load and `omerta_db_selftest` continues to pass on both backends (D-006 applies to this milestone too — its migration must behave identically on both).

## 12. Integration With Existing Systems

`modules/accounts/` (shared registration stub + `sv_repository.lua` + `sv_accounts.lua` + `sv_selftest.lua`). The database module gains only `UpsertIncrement`. `Omerta.Log.Audit`'s internals swap the stub for a DB write behind the unchanged signature — the swap M0 §7 promised. Nothing else in M0/M1 changes.

---

**Requesting approval to implement M2 as specified.** On approval: implementation, then the post-implementation report before M3's design review.
