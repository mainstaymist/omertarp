# Design Review — M4: Characters

Status: **APPROVED 2026-07-27 (approval-in-advance) — IMPLEMENTED.** See §13.
Milestone: M4 (roadmap Track A). Depends on: M0–M3. Consumed by: M5 (identity attaches to characters), M10 (rank), M19/M20 (injury and death), M21 (portraits), M22 (archive) — every gameplay system from here on.

> The project lead directed "Option C for the portrait pipeline then implement," which this review treats as approval-in-advance rather than a gate. One decision was made on their behalf and is cheap to veto: **Q-3, one active character per account per season** (§4).

## 1. Purpose

The character is the unit of play: the person a player *is* this season, distinct from the account behind them. M4 creates them, names them uniquely, captures their appearance and mugshot (D-011), enforces the account's seasonal path (D-009), loads them on join, and retires them at season end (D-010). It is the first milestone with networking and player-facing UI.

## 2. Responsibilities

**In scope:** characters table and repository (migration 3); name validation and season-wide uniqueness (Tech §3); creation flow — a validated net exchange plus a functional creation UI; appearance snapshot; portrait booth capture, upload, validation, storage, and on-demand fetch; one-active-character enforcement; spawn/load on join; status transitions (`alive → retired`, and `dead` reserved for M20); the D-010 season-end retirement listener; staff commands; self-test.

**Out of scope:** identity/introductions (M5 — characters are simply "Unknown" to each other until then), inventory (M9), rank/faction (M10), injury and death mechanics (M20 sets `dead`; M4 only defines the status), portrait *display* in newspapers (M21 — M4 proves the bytes round-trip), appearance customization beyond model/skin/bodygroups, and any HUD.

## 3. Public API

```lua
-- Server
Omerta.Characters.Get(ply)                 -- cached active character, or nil
Omerta.Characters.IsLoaded(ply)
Omerta.Characters.GetByID(id, cb)          -- cb(character, err) — offline lookup
Omerta.Characters.Create(ply, spec, cb)    -- cb(character, err) — validated, audited
Omerta.Characters.Retire(characterId, reason, cb)
Omerta.Characters.SetStatus(characterId, status, cb)   -- M20 sets "dead" through this
Omerta.Portraits.Fetch(characterId, cb)    -- cb(base64OrNil, err)

-- Shared (client pre-validates with the identical function the server enforces)
Omerta.Characters.ValidateName(first, last)     -- normalized first, last, key | nil, reason

-- Hooks
hook.Run("Omerta.CharacterCreated", ply, character)
hook.Run("Omerta.CharacterLoaded", ply, character)
hook.Run("Omerta.CharacterRetired", character, reason)
```

## 4. Q-3 — One active character per account per season

Exactly one. A player *is* one person this season; a second character would let one player hold two positions, launder knowledge between them, and hedge against permadeath — gutting the consequence design (GDD §19). A new character becomes possible only when the current one is `retired` or `dead`, and inherits nothing (D-009 track aside). Logged as **D-012** on acceptance.

## 5. Networking

First networked milestone. Three messages, all through M0's validated registry:

| Message | Direction | Payload |
|---|---|---|
| `characters.create` | client → server | first, last (text 24), model index (uint 8), skin (uint 4), path (uint 3) |
| `characters.portrait_upload` | client → server | base64 JPEG (text, capped) |
| `characters.state` | server → client | state code (uint 3): needs-creation / active / no-season / locked |
| `characters.portrait_fetch` / `portrait_data` | client ↔ server | character id (uint 32) / base64 (text) |

A client learns only its **own** character state; nothing about anyone else's character crosses the wire in M4. Model choice is an **index into a server-side table**, never a model path string — a client that could name arbitrary models could name anything the server would then set on a player.

## 6. Persistence

Migration 3:

```lua
characters: id(id), account_id ref NOT NULL, season_id ref NOT NULL,
            first_name text(24) NOT NULL, last_name text(24) NOT NULL,
            name_key text(56) NOT NULL,        -- normalized, lowercased "first last"
            status text(16) NOT NULL,          -- alive | retired | dead
            model text(128) NOT NULL, skin int DEFAULT 0, bodygroups json,
            portrait text(49152), portrait_at timestamp,   -- base64 JPEG (D-011)
            created_at timestamp NOT NULL, retired_at timestamp
            unique(season_id, name_key)        -- season-wide uniqueness (Tech §3, GDD §5)
            indexes: (account_id), (season_id), (status)
```

Uniqueness is enforced by the **database index**, not by a read-then-write check — two players submitting the same name in the same tick must not both succeed, and only a constraint guarantees that. The creation path treats a duplicate-key failure as "name taken."

Portraits live in the same row: base64 text (D-011), capped at 48 KB of base64 (~36 KB raw), immutable once set.

## 7. Security Considerations

- **Names**: validated server-side by the same pure function the client uses for feedback; control characters, markup, and digits rejected; length bounded; whitespace and shouting normalized. The client's copy is a courtesy, never a gate.
- **Models**: index into a server table (§5).
- **Portraits**: byte cap, base64 decode check, JPEG magic-byte check, one-shot per character, audited with the uploading account, staff-wipeable.
- **Path**: creation calls M3's `SetPath`, so D-009's matrix validates it — there is no path-setting bypass here either.
- **Season gating**: no active season means creation refuses cleanly (a configuration state, logged, never a crash).
- Every creation, retirement, and status change is audited.

## 8. Dependencies

M0 (module/config/log/net/hooks/selftest), M1 (DB + migration 3), M2 (accounts + `Omerta.AccountLoaded`), M3 (active season + path matrix + `Omerta.SeasonEnded`).

## 9. Future Extension Points

- `Omerta.CharacterLoaded` is where M5 (identity), M9 (inventory), and M10 (rank) attach.
- `status` already carries `dead` for M20; `bodygroups` json absorbs richer appearance without migration.
- `Omerta.Portraits.Fetch` is exactly what M21's newspaper and M22's archive will call.
- The model table is data; the period-appropriate roster (D-002) grows without code changes.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — read-then-write name uniqueness**: racy; the unique index is the only real guarantee.
**Rejected — client-supplied model paths**: a trivially abusable primitive (§5).
**Rejected — storing portraits as binary blobs**: the SQL layer rejects NUL bytes by design (M1 §7); base64 text keeps portraits inside the existing layer and normal backups.
**Rejected — a re-upload/"retake photo" path**: every extra upload moment is an extra abuse moment for zero gameplay value; the mugshot is a historical document (D-011).
**Rejected — multiple characters per account** (§4).

## 11. Testing Strategy

- **Headless**: name validation exhaustively (normalization, charset including accents, length in UTF-8 characters, markup/digit/control rejection, key generation); portrait validation (cap, base64, magic bytes); creation-spec validation; the full module flow against the mock driver — create, duplicate-name refusal, one-active enforcement, season-end retirement cascade.
- **In-engine**: `omerta_characters_selftest` — synthetic account and season-scoped rows, create, duplicate refusal, portrait store/fetch round-trip, retire, full cleanup. Plus the lived test: join, create a character through the UI, see the booth capture, reconnect and be loaded straight in.

## 12. Integration With Existing Systems

`modules/characters/`, `depends = { "database", "accounts", "seasons" }`. M2's lifecycle contract as always: schema and migration 3 in `OnLoad`; hooks, net registration, and DB work behind `WhenReady` in `OnEnable`. Nothing in M0–M3 changes.

## 13. Implementation Notes (post-implementation)

Implemented in `modules/characters/` (shared rules + net registry, repository, service, client UI, self-test). Headless suite grew to 99 checks. Notes:

- **Net messages are registered in the shared file**, not the server one. Both realms need every definition — the receiver to validate and dispatch, the sender to write the payload — and handlers only ever execute in their receiving realm. Caught during implementation; the original review implied server-side registration, which would have left the client unable to send anything.
- **Name rules as built**: control characters are rejected on the *raw* input before normalization (a newline is a rejection, not something to fold into a space); spacing is then collapsed and trimmed; capitalization is normalized *only* when the player typed all-one-case, so `McDonald` and `DiMeo` survive while `SALVATORE` and `salvatore` both become `Salvatore`; apostrophes, hyphens and interior spaces are allowed (`O'Brien`, `Lo Bianco`), with no leading, trailing or doubled punctuation; length is measured in **UTF-8 characters, not bytes**, so `José` counts as four.
- **`Omerta.DB.NULL` in UPDATEs**: clearing a portrait writes the explicit NULL sentinel, since a bare `nil` would break the params array.
- **Portrait booth**: `render.Capture` reads the back buffer, so the model must genuinely be on screen — the capture runs in `PostRender` against the booth panel's screen rectangle, cropped square so framing is resolution-independent. Fixed camera at head height, idle animation disabled: a mugshot, not a photoshoot.
- **One-shot upload is enforced twice**: an in-memory flag per session and `WHERE portrait IS NULL` in the UPDATE, so even a replayed packet cannot overwrite a stored mugshot.
- **Characterless players are gated**: frozen, hidden and invulnerable until a character loads, released on `Omerta.CharacterLoaded`. Crude but correct until M8's UI framework and proper spawn handling land.
- **Path rejection does not undo a character**: if D-009's matrix refuses the chosen path (e.g. police mid-season), the character still exists and the account keeps its current path; the refusal is logged. Losing a validated character over a path technicality would be worse than the inconsistency.
- **Test-shim additions**: `IsValid` and a minimal `hook` table, needed because player-cache lookups and `Omerta.AccountLoaded` run outside `InEngine` guards. Everything genuinely engine-bound remains behind the flag.
- Two of my own bugs were caught by the new tests before shipping: name normalization silently accepting newlines, and the portrait validator's argument contract in the test being wrong rather than the code.
- **A race the review never sequenced, found in the field:** the client captured and uploaded the mugshot on the frame after the player clicked *Enter the city*, but creating a character costs the server two database round-trips, so the upload arrived ~16 ms before the character existed and was discarded. The review said "capture at creation" without specifying that the *upload* must wait for creation to complete. Fixed by splitting the two: capture still happens immediately (the booth must be on screen), but the bytes are held client-side and uploaded when the server confirms `ACTIVE`, which it sends only after the character is cached. A failed creation discards the held image. Diagnosed entirely from the two log lines this milestone's diagnostics were added to produce.
- **One escaped to the server and was fixed after the first client boot:** `cl_creation.lua` read `Omerta.Characters.STATE` at include time, but the loader sorted files alphabetically, so `cl_` ran before `sh_` and the constant did not exist yet (server was unaffected — `sh_` precedes `sv_`). Fixed in the loader rather than the symptom: `sh_` files now load before realm files, since shared code defines the contracts realm code consumes. See M0 §13; regression-tested in `tests/test_module.lua`.

In-engine acceptance (user-side): pull, restart (watch for `applying migration 3: characters`), ensure a season is active, then `omerta_characters_selftest` (expect 11/11). Then the lived test: join the server, create a character through the booth UI, and reconnect — you should be loaded straight in with no creation screen. `omerta_portrait_clear <id>` wipes an abusive mugshot.
