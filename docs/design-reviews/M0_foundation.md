# Design Review — M0: Gamemode Skeleton and Core Framework

Status: **AWAITING APPROVAL — no implementation until approved.**
Milestone: M0 (roadmap Track A). Depends on: nothing. Everything depends on it.

## 1. Purpose

Produce a bootable, from-scratch Garry's Mod gamemode containing the structural machinery every later system runs on: a module loader with dependency-ordered lifecycles, a schema-validated configuration system, structured logging with an audit sink stub, disciplined networking conventions, and a pure-Lua core that can be unit-tested outside the game. M0 contains **zero gameplay**. Its success criterion is that M1–M24 can each be added as a module without touching anything M0 shipped.

## 2. Responsibilities

**In scope:**

- Gamemode boot skeleton (`init.lua` / `cl_init.lua` / `shared.lua` as thin bootstraps only).
- Module system: registration, dependency declaration, deterministic load order, lifecycle hooks, per-realm file inclusion conventions.
- Configuration: layered (defaults → server config), schema-validated, with a hard split between shared config (replicated) and server-secret config (never leaves the server).
- Logging: leveled, per-module channels, console + file outputs, and an `Audit(...)` API stub that M2 later backs with the database.
- Networking core: a registration wrapper around the `net` library imposing validation, rate limiting, and naming conventions on every message from day one.
- Small utility library (table/string helpers, assertion/error helpers, realm guards) — only what M0 itself needs; utilities grow on demand, not speculatively.

**Explicitly out of scope:** database access (M1), accounts/persistence (M2), any HUD beyond removing nothing yet (M6/M8 own suppression), any entity, item, or interaction.

## 3. Public API

All code lives under a single global namespace `Omerta` (D-001). Sketch of the surfaces M0 commits to (signatures final at implementation, semantics fixed here):

```lua
-- Module system (shared)
Omerta.Module.Register({
    name = "example",            -- unique key
    depends = { "log", "config" }, -- load-order dependencies
    -- lifecycle (each optional, called in dependency order):
    OnLoad     = function(self) end,  -- files included, config available
    OnEnable   = function(self) end,  -- all modules loaded; safe to reference others
    OnReload   = function(self) end,  -- lua refresh / map change housekeeping
})
Omerta.Module.Get(name)          -- nil-safe accessor
Omerta.Module.IsEnabled(name)

-- Configuration (shared read; definition server/shared as declared)
Omerta.Config.Define("module.key", {
    type = "number", default = 6, min = 1,   -- schema, validated at boot
    scope = "shared" | "server",             -- server scope never replicates
    description = "...",
})
Omerta.Config.Get("module.key")              -- validated value; error if undefined key
-- (runtime mutation/replication deliberately deferred to a later milestone)

-- Logging (shared; file output server-side)
Omerta.Log.Info(channel, fmt, ...)      -- also: Debug/Warn/Error
Omerta.Log.Audit(event, data)           -- server-only stub; M2 gives it storage.
                                        -- Until then it writes to the server log
                                        -- in the same envelope shape M2 will persist.

-- Networking (see §5)
Omerta.Net.Register(name, def)          -- server + client registration
Omerta.Net.Send(name, payload, targets) -- server → client(s)
Omerta.Net.Request(name, payload)       -- client → server (validated, rate-limited)
```

File layout convention (enforced by the loader):

```
gamemodes/omertarp/
  gamemode/
    init.lua, cl_init.lua, shared.lua      -- thin bootstraps
    core/                                   -- M0 itself (loader, config, log, net, util)
    modules/<name>/                         -- one directory per module
      sh_*.lua   sv_*.lua   cl_*.lua        -- realm by prefix; auto-included, auto-AddCSLuaFile'd
```

## 4. Data Model

No persistent data in M0. The config schema registry (key → type/default/scope/constraints) is the only structured data, held in memory and rebuilt at boot. Config files are plain Lua tables under the server's data/config path; malformed or schema-violating config **fails the boot loudly** rather than silently defaulting — wrong config on this project (e.g., a DB backend typo) must never pass unnoticed.

## 5. Networking

M0 ships conventions and enforcement, not messages:

- Every net message is declared via `Omerta.Net.Register(name, def)` where `def` states realm direction, a payload schema (field names/types/bounds), a rate limit (per-player token bucket, default conservative), and the handler. Unregistered names cannot be sent; registration collisions error at boot.
- Client→server handlers run **validation before handler code**: type/bounds checks from the schema, sender sanity, rate-limit consumption. Failing messages are dropped and logged (audit envelope), never partially processed.
- Pooled network strings under a single `omerta/` prefix; payloads via net-library primitives with explicit sizes (no unbounded `net.WriteTable` in the hot path — the wrapper provides typed writers generated from the schema).
- Server→client sends take explicit target lists — there is deliberately **no broadcast-to-all convenience**, because under the information philosophy almost nothing should ever go to everyone (Tech §2: "never replicate the full identity map"). Broadcasting requires typing out `player.GetAll()`, which should feel wrong.

## 6. Persistence

None in M0. The design constrains M1: the config system's server-secret scope is where M1's backend selection and credentials will live; `Omerta.Log.Audit`'s envelope (event name, actor, subject, data, timestamp) is shaped now so M2 can persist it without call-site changes.

## 7. Security Considerations

- **Server authority is structural**: the net wrapper makes unvalidated client input impossible to accept accidentally — there is no raw receive path in module code.
- **Secrets stay server-side by type**: `scope = "server"` config physically has no replication path; DB credentials (M1) can never leak by omission.
- **Rate limiting by default**: every client-originated message gets a limit unless the declaration raises it — flood protection is opt-out with justification, not opt-in.
- **Realm hygiene by convention + loader**: `sv_` files are never AddCSLuaFile'd; a client cannot even download server logic. The loader errors on realm-ambiguous filenames.
- **Audit-first culture**: the audit API exists from boot so M1+ never has an excuse to skip logging (Tech §23's list is long; the habit starts at M0).
- Threats deliberately deferred with their systems: identity leakage (M5/M6 + S3), inventory duplication (M9), economy race conditions (M1 transactions, M11).

## 8. Dependencies

None — M0 is the root. It uses only the base `gamemode` system and stock GMod Lua APIs. No third-party frameworks or libraries (see §10).

## 9. Future Extension Points

- **Every later service is a module**: M1's `db`, M2's `accounts`, through M24 — each registers with `depends`, gets lifecycle ordering, config keys, log channels, and net registration for free.
- **Config schema grows per module** without central edits (modules define their own keys under their own prefix).
- **Audit sink swap** (M2) turns the stub into DB-backed logging with zero call-site changes.
- **Net payload schemas** are the natural place to later hang compression, delta encoding, or per-message encryption if ever needed.
- **Headless core** (see §11) is what lets later pure-logic systems (sentencing math, evidence scoring, name validation) ship with real unit tests.

## 10. Architecture Rationale and Alternatives Rejected

**Why this architecture:** the project's constraints — years of expansion, one-milestone-at-a-time delivery, strict server authority, information-minimal networking — all reward paying the module/convention tax at hour zero. Every later milestone review can describe itself as "a module with these config keys, these net messages, these audit events," which keeps reviews comparable and integration mechanical.

**Rejected — building on DarkRP or another RP framework:** explicitly forbidden by spec (Tech §1) and genuinely wrong here: those frameworks' core assumptions (jobs, global chat, scoreboards, money HUDs) are precisely what this design removes; we would spend M0-scale effort deleting framework behavior instead of adding ours.

**Rejected — Helix/NutScript-style base:** closer in spirit (characters, inventories), but still imports large opinionated systems we would fight (factions/whitelists, chat frameworks, UI stacks), adds an external maintenance dependency, and violates the from-scratch mandate. The parts worth having (schema'd items, character abstraction) are re-derived under our own philosophy in M4/M9 where our requirements (per-observer identity, physical currency) diverge sharply from theirs anyway.

**Rejected — plain file includes without a loader:** the zero-framework option. Fails at scale predictably: implicit load-order coupling, ad-hoc net handling drift, config sprawl — the exact "hacky systems / duplicated logic" the project brief bans.

**Rejected — many globals / flat namespace:** one `Omerta` root keeps the addon-collision surface minimal and makes leak auditing (S3) tractable: anything of ours is findable by prefix.

## 11. Testing Strategy

- **Headless unit tests**: `core/` written engine-agnostic where possible (loader resolution, config validation, schema checks, rate-limit math run under plain Lua); a tiny shim fakes the few engine calls. Tests live in-repo and run in CI (glualint + unit suite) — this is the harness later logic-heavy milestones inherit (review improvement #2).
- **In-engine smoke test**: gamemode boots on an empty map with zero errors; a `demo` module exercises every lifecycle hook, config type, log level, and one round-trip validated/rate-limited net message; boot with deliberately broken config must fail loudly.
- **Manual acceptance** (matches roadmap "testable when"): dependency-order verification with a three-module chain; rate-limit flood test from a client console script; confirmation that `sv_` files are absent from client Lua cache.

## 12. Integration With Existing Systems

Nothing exists yet — M0 *is* the integration point. The concrete handoffs it must leave ready: server-secret config slots for M1's backend choice; the audit envelope for M2; the module lifecycle every subsequent review will cite.

---

**Requesting approval to implement M0 as specified.** On approval: implementation, then the standard post-implementation report (what was built, why, extension points, integration points, test results) before M1's design review begins.
