# Design Review — M3: Seasons

Status: **APPROVED 2026-07-27 — IMPLEMENTED** (D-009 and D-010 logged). See §13 for implementation notes.
Milestone: M3 (roadmap Track A). Depends on: M0, M1, M2. Consumed by: M4 (characters are season-scoped and creation requires an active season + chosen path), M10 (faction membership respects the path matrix), M23 (seasonal reset drives off the lifecycle hooks) — and ultimately everything, since all seasonal data keys on SeasonID from birth (Tech §2, §22).

> **Approving this review also rules on two open design questions** — Q-2 (seasonal-allegiance semantics, §4a) and Q-4 (season-end character handling, §4b). On approval they are logged as D-009 and D-010. Amendments welcome before approval.

## 1. Purpose

Seasons are the game's temporal container: a roughly four-week arc (GDD §3) inside which characters, organizations, wealth, and cases live, and at whose end they reset while history archives (Tech §22). M3 builds the container itself — the season entity, its lifecycle, the one-active-season invariant, and the per-account **path selection** (criminal / police / independent) with server-enforced transition rules. It deliberately does *not* build what fills the container (characters, factions) or what empties it (M23's archival cascade); it provides the states and hooks those systems attach to.

## 2. Responsibilities

**In scope:** seasons table and lifecycle (`setup → active → ended`); exactly-one-active invariant; account–season path records; the path transition matrix (server-validated, table-driven, audited); staff console commands for season control (no admin UI until M24); season/path caching and hooks; migration 2; self-test.

**Out of scope:** character retirement mechanics (M4 owns characters; M3 fires the hook it will listen to), archival/reset processing (M23), path-choice UI (M4's character-creation flow; M3 has **no networking**), faction membership itself (M10 — it *consumes* the matrix), informant/corruption states (Phase 5 — see §4a note), season "winner" computation (M23).

## 3. Public API

Server-only. No net messages (§5).

```lua
Omerta.Seasons.GetActive()             -- cached season table or nil (fresh servers have none)
Omerta.Seasons.GetPath(ply)            -- "criminal" | "police" | "independent" | nil (not chosen)
Omerta.Seasons.SetPath(ply, path, cb)  -- initial choice only; validated, audited
Omerta.Seasons.ConvertToCriminal(ply, reason, cb)  -- the independent→criminal transition;
                                                    -- called by M10's recruitment flow
Omerta.Seasons.LeavePolice(ply, reason, cb)        -- police→independent (resignation/expulsion);
                                                    -- called by M10's department flow

-- Lifecycle (staff console commands wrap these; M23 will drive End's cascade)
Omerta.Seasons.Create(opts, cb)        -- label, ruleset_version, length_days -> setup state
Omerta.Seasons.Start(seasonId, cb)     -- setup -> active; refuses if another season is active
Omerta.Seasons.End(seasonId, cb)       -- active -> ended; fires the hook, nothing more

-- Hooks (the extension surface)
hook.Run("Omerta.SeasonStarted", season)
hook.Run("Omerta.SeasonEnded", season)          -- M4 retires characters; M23 archives
hook.Run("Omerta.PathChosen", ply, path)
hook.Run("Omerta.PathChanged", ply, old, new, reason)
```

Staff commands (server console / superadmin): `omerta_season_status`, `omerta_season_create <label>`, `omerta_season_start <id>`, `omerta_season_end <id>`, `omerta_seasons_selftest`.

## 4. The Two Rulings

### 4a. Q-2 — Seasonal allegiance: what the path lock actually permits

The GDD binds each account to one path per season (GDD §3) but also makes recruiting independents into families core gameplay (GDD §4.3) and never says what a dead criminal's next character is. Proposed semantics: **the path is a track commitment, not a faction assignment**, with this transition matrix (table-driven data, enforced server-side, every transition audited):

| From ↓ To → | criminal | police | independent |
|---|---|---|---|
| *(unchosen)* | ✅ initial choice | ✅ initial choice | ✅ initial choice |
| criminal | — | ❌ never | ❌ never |
| police | ❌ never | — | ✅ resignation / expulsion (one-way) |
| independent | ✅ family recruitment (one-way) | ❌ never | — |

- **Criminal path** means *eligible for family life*, not member of one: recruitment, rank, and expulsion are M10's in-world business. Expulsion from a family leaves you criminal-track (an outcast associate, not a civilian).
- **Independent → criminal** is the recruitment transition the GDD requires, and it is one-way for the season: family life marks you.
- **Police → independent** covers resignation and expulsion. An ex-cop may never join a family in the same season, and criminals may never join the department: both directions would launder a season of one side's knowledge into the other — precisely the metagaming the identity design exists to prevent. Undercover work is a designed Phase-5 feature, not an accidental path change.
- **Police path is chosen at season start only** (department vetting, in fiction; in mechanics, the highest-trust track shouldn't be joinable by whoever wandered in mid-season). Staff may make exceptions manually.
- **Replacement characters inherit the account's current track.** A dead soldier's player stays criminal-track; the new character starts unaffiliated and must be re-recruited (GDD §19.3's no-restoration rule, applied to paths).
- Informant and corrupt-cop states are **covert overlays, not path changes** — a flipped criminal remains criminal-track; a bought officer remains police-track. Their milestones build on this without touching the matrix.

### 4b. Q-4 — Season end: living characters retire

When a season ends, **every living character retires automatically** — narratively, they leave the city; mechanically, status `retired`, eligible for archive records (M22). Nothing carries into the next season except account-level persistence (cosmetics, titles, stats — GDD §3), and everyone creates a fresh character. This matches the Tech data model (characters carry SeasonID from birth), gives the archive clean season boundaries, and avoids every messy alternative (carrying characters across resets would drag their knowledge, relationships, and records along — contradicting the wipe). M4 implements the retirement listener; M3 fires the hook.

## 5. Networking

**None.** Path choice reaches the server through M4's character-creation flow (its own validated net message calling `SetPath`); season state replicates to clients only when something needs displaying, which is also M4+. Third consecutive zero-networking milestone — the information-philosophy default holds until a UI actually needs a fact.

## 6. Persistence

Migration 2, via the M1 DSL:

```lua
seasons:         id(id), label text(64) NOT NULL, state text(16) NOT NULL ("setup"|"active"|"ended"),
                 ruleset_version text(32) NOT NULL DEFAULT "1",
                 created_at timestamp NOT NULL, started_at timestamp, ends_at timestamp, ended_at timestamp,
                 summary json          -- filled by M23 at archive time
                 indexes: (state)
account_seasons: account_id ref NOT NULL, season_id ref NOT NULL,
                 path text(16) NOT NULL, chosen_at timestamp NOT NULL
                 primary(account_id, season_id), indexes: (season_id)
```

- `path` holds the **current** track; the audit log is the history (`season.path_chosen`, `season.path_changed` events carry old/new/reason) — no second column duplicating what audit already records.
- The **one-active invariant** is enforced in code (`Start` refuses while any season is active) and re-checked at boot: if the table ever holds two active seasons (crash mid-transition), the server refuses to start loudly, M1-style, rather than guessing.
- The active season and each online player's path are cached in memory; the path loads via the `Omerta.AccountLoaded` hook (M2's extension point, consumed for the first time) and is stored on the account object.
- Config: `seasons.default_length_days` (28, per GDD §3) used by `Create` to compute `ends_at`. The season does **not** auto-end at `ends_at` — ending a season is a deliberate staff/M23 action; the timestamp is the schedule, not a trigger (an unattended timer firing a server-wide reset mid-raid would be indefensible).

## 7. Security Considerations

- Path transitions execute only through the matrix — there is no "set path" primitive that skips validation, and every transition writes an audit event with account, old, new, and reason.
- Lifecycle mutations are staff-only (console/superadmin gate, same as the self-tests) and audited (`season.created/started/ended` with the acting staff member where applicable).
- No client input exists in this milestone; when M4 forwards a player's path choice, it arrives through the M0 net layer's validation and lands in `SetPath`'s matrix check regardless.
- Fresh-install posture: no season means character creation (M4) simply refuses — a configuration state, loudly logged, never a crash.

## 8. Dependencies

M0 (module/config/log/hooks), M1 (DB + migration 2), M2 (accounts — path records reference account ids; `Omerta.AccountLoaded` carries the path into the cache).

## 9. Future Extension Points

- `Omerta.SeasonEnded` is where M4 (retirement), M10 (org reset), and M23 (the full archival cascade) attach — M3 never needs to change for them.
- `ruleset_version` lets M23+ vary rules per season without schema changes.
- `summary` json is reserved for M23's winner/awards output (Tech §2 "Winner summaries").
- The transition matrix is data: Phase-5 systems (witness protection's forced retirement, staff-mediated exceptions) add rows, not code paths.
- Per-season config overrides (event seasons, rule experiments) can hang off the season record later.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — auto-creating/auto-ending seasons on a timer.** Seasons are the server's largest ritual; they start and end when a human (or M23's supervised job) says so. `ends_at` schedules, staff execute.

**Rejected — a `current_path` + `original_path` pair.** The audit log already is the history; duplicating it in columns invites divergence.

**Rejected — putting path on the account row.** Path is a *per-season* fact; on the account it would need clearing every season and would lose history. The junction table is the honest shape.

**Rejected — letting M3 perform season-end processing.** The cascade (retire, reset, archive) belongs to the systems that own the data, coordinated by M23; M3 owning it would couple the container to everything it contains — the exact giant-hook antipattern the project brief bans.

**Rejected — police as a mid-season joinable faction.** Covered in §4a; the matrix is the design.

## 11. Testing Strategy

- **Headless:** the transition matrix exhaustively (every from/to/reason cell); lifecycle state validation (illegal `Start`/`End` transitions, double-active refusal, boot-time invariant check); migration 2 rendering; repository SQL and the full module boot against the mock driver (the established pattern).
- **In-engine** (`omerta_seasons_selftest`): careful by design — it must **never touch the live season's state**. It creates a season in `setup` state (never started), exercises path selection and both legal transitions using synthetic accounts against the *active* season (skipping those steps with a clear message if no season is active), verifies an illegal transition is refused, and deletes every synthetic row including audit. Real `Start`/`End` are exercised headless and by actual staff usage — a self-test that could end your live season is worse than no self-test.

## 12. Integration With Existing Systems

`modules/seasons/` (stub + repository + service + selftest), `depends = { "database", "accounts" }`. Follows M2's lifecycle contract exactly: schema + migration 2 in `OnLoad`; hooks, cache warming, and the boot invariant check in `OnEnable` behind `WhenReady`. First consumer of `Omerta.AccountLoaded`. Nothing in M0–M2 changes.

---

## 13. Implementation Notes (post-implementation)

Implemented in `modules/seasons/` (stub, repository, service, self-test). Headless suite grew to 85 checks, including the transition matrix exercised **exhaustively** — every from/to/reason combination, 60 cells, asserted against an independent statement of the D-009 rules. Notes:

- **The matrix is one table** (`TRANSITIONS` in `sv_seasons.lua`); every path change funnels through `applyTransition` — there is no bypass primitive. Future transition kinds (witness protection, staff exceptions) are new rows, as designed.
- **`ends_at` is computed at `Start`**, not `Create` (start time isn't known at creation; the design's "Create computes it" was off by one lifecycle step). Still a schedule, never a trigger.
- **Idempotence-safe mutations:** `StartSeason`/`EndSeason` UPDATEs carry `AND state = ?` guards, so a duplicated or stale staff command cannot re-start an ended season.
- **Invariant failure is a module-failed state** (loud boot error, all season APIs refuse), mirroring M1's database-failed posture — GMod offers no clean way to halt a booted server, so "refuse everything loudly" is the honest implementation of "refuse to start."
- **Ending a season clears online players' cached paths**; historical `account_seasons` rows are deliberately kept — they are the season's history.
- First consumer of `Omerta.AccountLoaded` works as designed: the player's current-season path rides on the cached account object.
- **Self-test safety holds:** the suite's season never leaves `setup`, its delete is guarded by `label AND state = 'setup'`, and path steps self-skip with a clear message when no live season is active (start one and re-run for full coverage). Real `Start`/`End` are covered headless.

In-engine acceptance (user-side): pull, restart (watch for `applying migration 2: seasons and path selection`), then `omerta_seasons_selftest`. For full coverage: `omerta_season_create Season One`, `omerta_season_start 1`, re-run the self-test (path steps now execute), and `omerta_season_status` at will. Leave the season running — M4 will need it.
